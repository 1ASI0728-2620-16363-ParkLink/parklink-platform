import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/location_point.dart';
import '../../domain/models/tracking_session.dart';
import '../services/api_client.dart';
import '../services/background_tracking_service.dart';
import '../services/location_service.dart';
import '../services/session_store.dart';

class DriverPresenceRepository extends ChangeNotifier {
  DriverPresenceRepository({
    required ApiClient apiClient,
    required LocationService locationService,
    required BackgroundTrackingService backgroundTrackingService,
    required SessionStore sessionStore,
  }) : _apiClient = apiClient,
       _locationService = locationService,
       _backgroundTrackingService = backgroundTrackingService,
       _sessionStore = sessionStore {
    _backgroundTrackingService.addListener(_trackingChanged);
    _sessionStore.addListener(_sessionChanged);
  }

  static const _presencePolicy = TrackingPolicy(
    intervalSeconds: 3,
    distanceFilterMeters: 0,
  );

  final ApiClient _apiClient;
  final LocationService _locationService;
  final BackgroundTrackingService _backgroundTrackingService;
  final SessionStore _sessionStore;

  StreamSubscription<LocationPoint>? _subscription;
  /// Reintento de la captura. Sin esto, un solo error del proveedor de GPS
  /// dejaba al conductor sin compartir ubicacion hasta que abriera la app.
  Timer? _retryTimer;
  int _retryAttempt = 0;
  Future<void>? _captureTransition;
  bool _captureStateDirty = false;
  bool _manuallyPaused = false;
  LocationPoint? _pendingLocation;
  LocationPoint? _lastLocation;
  bool _sendingLocation = false;
  bool _loaded = false;
  bool _available = false;
  bool _updating = false;
  String? _lastError;
  DateTime? _lastSentAt;

  bool get loaded => _loaded;
  bool get available => _available;
  bool get updating => _updating;
  bool get isSharingLocation => _subscription != null;
  bool get pausedForRoute =>
      _available && _backgroundTrackingService.blocksPresenceTracking;
  String? get lastError => _lastError;
  DateTime? get lastSentAt => _lastSentAt;
  LocationPoint? get lastLocation => _lastLocation;

  Future<void> load() async {
    if (!_sessionStore.hasOperationalSession ||
        _sessionStore.user?.role != 'DRIVER') {
      await stop();
      return;
    }
    // Ahora entra desde el arranque y desde `resumeIfAvailable`: sin esta
    // guarda, dos llamadas a la vez pelearian por el PUT de disponibilidad.
    if (_updating) return;
    _updating = true;
    _lastError = null;
    notifyListeners();
    try {
      final response = await _apiClient.getJson('/mobile/presence');
      _available = _readAvailable(response) ?? false;

      // Primero el permiso, despues anunciarse. Al reves el servidor se queda
      // creyendo que el conductor esta disponible mientras la app no puede
      // enviar ni una posicion, y en el panel aparece como conectado y sin
      // ubicacion para siempre.
      //
      // Basta el permiso de "mientras se usa": compartir presencia no necesita
      // segundo plano. `prepareForStart()` exige "Siempre" y en iOS lanza
      // excepcion si no la hay, que es lo que corresponde al seguimiento de un
      // servicio, no a esto.
      final permiso = await _locationService.prepareContinuousTracking();
      final puedeCompartir =
          permiso.permission == LocationPermission.whileInUse ||
          permiso.permission == LocationPermission.always;

      if (puedeCompartir && !_available) {
        // El conductor sale en el mapa desde que inicia sesion, tenga o no un
        // servicio asignado.
        final confirmado = _readAvailable(
          await _apiClient.putJson('/mobile/presence', {'available': true}),
        );
        _available = confirmado ?? false;
      } else if (!puedeCompartir && _available) {
        // Sin permiso no habra posiciones: se retira la disponibilidad para que
        // el panel no lo muestre conectado sin poder ubicarlo.
        await _apiClient.putJson('/mobile/presence', {'available': false});
        _available = false;
        _lastError =
            'Concede el permiso de ubicación para aparecer en el mapa.';
      }

      _loaded = true;
      _manuallyPaused = false;
      await _syncCapture();
    } catch (error) {
      _available = false;
      _loaded = false;
      _lastError = error.toString();
      await _stopCapture();
    } finally {
      _updating = false;
      notifyListeners();
    }
  }

  Future<bool> setAvailable(bool value) async {
    if (_updating || !_sessionStore.hasOperationalSession) return false;
    _updating = true;
    _lastError = null;
    notifyListeners();
    try {
      if (value) {
        _manuallyPaused = false;
        await _backgroundTrackingService.prepareForStart();
      } else {
        _manuallyPaused = true;
        await _stopCapture();
      }

      final response = await _apiClient.putJson('/mobile/presence', {
        'available': value,
      });
      var confirmed = _readAvailable(response);
      confirmed ??= _readAvailable(
        await _apiClient.getJson('/mobile/presence'),
      );
      _available = confirmed ?? false;
      _loaded = true;
      _manuallyPaused = !value || _available != value;
      await _syncCapture();
      return _available == value;
    } catch (error) {
      _lastError = error.toString();
      _manuallyPaused = true;
      await _stopCapture();
      return false;
    } finally {
      _updating = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _loaded = false;
    _available = false;
    _manuallyPaused = true;
    _pendingLocation = null;
    _lastSentAt = null;
    await _stopCapture();
    notifyListeners();
  }

  Future<void> pause() async {
    _manuallyPaused = true;
    await _stopCapture();
    notifyListeners();
  }

  Future<void> pauseForRouteStart() async {
    await _stopCapture();
    notifyListeners();
  }

  Future<void> resumeIfAvailable() async {
    _manuallyPaused = false;
    // Si no se esta compartiendo, puede ser que el permiso se concediera desde
    // los Ajustes del sistema con la app en segundo plano. `load()` lo vuelve a
    // comprobar y se anuncia; `_syncCapture()` solo reanudaria lo ya montado.
    if (_subscription == null) {
      await load();
      return;
    }
    await _syncCapture();
  }

  Future<void> disableForLogout() async {
    _manuallyPaused = true;
    await _stopCapture();
    if (_sessionStore.hasOperationalSession) {
      try {
        await _apiClient.putJson('/mobile/presence', {'available': false});
      } catch (_) {
        // Logout still revokes local credentials and location capture.
      }
    }
    _available = false;
    _loaded = false;
    _lastSentAt = null;
    notifyListeners();
  }

  Future<void> _syncCapture() {
    final existing = _captureTransition;
    if (existing != null) {
      _captureStateDirty = true;
      return existing;
    }
    final transition = _applyCaptureState();
    _captureTransition = transition;
    return transition.whenComplete(() {
      if (identical(_captureTransition, transition)) {
        _captureTransition = null;
      }
      if (_captureStateDirty) {
        _captureStateDirty = false;
        unawaited(_syncCapture());
      }
    });
  }

  Future<void> _applyCaptureState() async {
    final shouldShare =
        _loaded &&
        _available &&
        !_manuallyPaused &&
        _sessionStore.hasOperationalSession &&
        !_backgroundTrackingService.blocksPresenceTracking;
    if (!shouldShare) {
      _cancelCaptureRetry();
      await _stopCapture();
      return;
    }
    if (_subscription != null) return;

    try {
      final stream = await _locationService.positionStream(
        _presencePolicy,
        presenceMode: true,
      );
      if (!_available ||
          _manuallyPaused ||
          !_sessionStore.hasOperationalSession ||
          _backgroundTrackingService.blocksPresenceTracking) {
        return;
      }
      // Una posicion de una vez, ya: el stream puede tardar en dar el primer
      // fix y el conductor debe salir en el mapa en cuanto concede el permiso.
      unawaited(_enviarPrimeraPosicion());
      _subscription = stream.listen(
        _locationReceived,
        onError: (Object error, StackTrace stackTrace) {
          _lastError = error.toString();
          unawaited(_stopCapture());
          _scheduleCaptureRetry();
          notifyListeners();
        },
        onDone: () {
          // El stream se cerro solo: mientras el conductor siga disponible hay
          // que volver a levantarlo, no quedarse esperando que abra la app.
          _subscription = null;
          _scheduleCaptureRetry();
          notifyListeners();
        },
        cancelOnError: false,
      );
      // Arranco bien: se limpia la cuenta de intentos para que el proximo
      // corte vuelva a empezar por la espera corta.
      _cancelCaptureRetry();
      notifyListeners();
    } catch (error) {
      _lastError = error.toString();
      await _stopCapture();
      _scheduleCaptureRetry();
      notifyListeners();
    }
  }

  /// Fuerza un primer punto sin esperar al stream. Si falla no importa: el
  /// stream seguira enviando en cuanto tenga senal.
  Future<void> _enviarPrimeraPosicion() async {
    if (_lastLocation != null) return;
    try {
      final punto = await _locationService.currentLocation();
      _locationReceived(punto);
    } catch (_) {
      // Sin fix todavia; el stream se encarga.
    }
  }

  void _locationReceived(LocationPoint point) {
    _pendingLocation = point;
    _lastLocation = point;
    if (!_sendingLocation) unawaited(_sendLatestLocation());
  }

  Future<void> _sendLatestLocation() async {
    _sendingLocation = true;
    try {
      while (_pendingLocation != null &&
          _available &&
          !_manuallyPaused &&
          _sessionStore.hasOperationalSession &&
          !_backgroundTrackingService.blocksPresenceTracking) {
        final point = _pendingLocation!;
        _pendingLocation = null;
        final deviceId = _sessionStore.serverDeviceId;
        if (deviceId == null) {
          // Salir en silencio deja al conductor "disponible" en el panel y sin
          // ubicacion, sin que nadie sepa por que. Que al menos lo diga.
          _lastError =
              'El teléfono aún no terminó de registrarse. Cierra y vuelve a abrir la app.';
          notifyListeners();
          return;
        }
        try {
          await _apiClient.postJson('/mobile/presence/location', {
            'deviceId': deviceId,
            'clientPositionId': const Uuid().v4(),
            'capturedAt': (point.capturedAt ?? DateTime.now().toUtc())
                .toUtc()
                .toIso8601String(),
            'latitude': point.latitude,
            'longitude': point.longitude,
            'accuracy': point.accuracy.isFinite
                ? point.accuracy.clamp(0, 10000).toDouble()
                : 0.0,
            if (point.speed != null &&
                point.speed!.isFinite &&
                point.speed! >= 0 &&
                point.speed! <= 150)
              'speedMps': point.speed,
            if (point.heading != null &&
                point.heading!.isFinite &&
                point.heading! >= 0 &&
                point.heading! <= 360)
              'headingDeg': point.heading,
            if (point.altitude != null &&
                point.altitude!.isFinite &&
                point.altitude! >= -1000 &&
                point.altitude! <= 20000)
              'altitudeM': point.altitude,
            if (point.provider.trim().isNotEmpty &&
                point.provider.trim().length <= 40)
              'provider': point.provider.trim(),
            'isMocked': point.isMocked,
          });
          _lastSentAt = point.capturedAt ?? DateTime.now().toUtc();
          _lastError = null;
          notifyListeners();
        } catch (error) {
          _lastError = error.toString();
          notifyListeners();
        }
      }
    } finally {
      _sendingLocation = false;
      if (_pendingLocation != null &&
          _available &&
          !_manuallyPaused &&
          !_backgroundTrackingService.blocksPresenceTracking) {
        unawaited(_sendLatestLocation());
      }
    }
  }

  Future<void> _stopCapture() async {
    final subscription = _subscription;
    _subscription = null;
    _pendingLocation = null;
    await subscription?.cancel();
  }

  /// Esperas entre reintentos, en segundos.
  ///
  /// Empieza corto porque la mayoria de los cortes son un parpadeo del
  /// proveedor, y se alarga para no encender el GPS cada cinco segundos cuando
  /// el problema es de fondo —permiso revocado, GPS apagado— y solo gastaria
  /// bateria, que es justo lo que hace que el sistema mate la app.
  static const _esperasDeReintento = <int>[5, 10, 20, 40, 60];

  void _scheduleCaptureRetry() {
    if (_retryTimer?.isActive == true) return;
    final indice = _retryAttempt < _esperasDeReintento.length
        ? _retryAttempt
        : _esperasDeReintento.length - 1;
    _retryAttempt += 1;
    _retryTimer = Timer(Duration(seconds: _esperasDeReintento[indice]), () {
      _retryTimer = null;
      // _syncCapture y no _applyCaptureState: serializa las transiciones y
      // vuelve a comprobar que el conductor siga disponible antes de encender.
      unawaited(_syncCapture());
    });
  }

  void _cancelCaptureRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  bool? _readAvailable(Map<String, dynamic> response) {
    final data = response['data'];
    final root = data is Map<String, dynamic> ? data : response;
    final presence = root['presence'];
    final source = presence is Map<String, dynamic> ? presence : root;
    final value = source['available'];
    return value is bool ? value : null;
  }

  void _trackingChanged() => unawaited(_syncCapture());

  void _sessionChanged() {
    if (_sessionStore.hasOperationalSession) return;
    unawaited(stop());
  }

  @override
  void dispose() {
    _backgroundTrackingService.removeListener(_trackingChanged);
    _sessionStore.removeListener(_sessionChanged);
    _retryTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
