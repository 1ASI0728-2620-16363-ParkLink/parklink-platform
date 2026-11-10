import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/location_point.dart';
import '../../domain/models/tracking_session.dart';
import '../repositories/tracking_repository.dart';
import 'local_database.dart';
import 'location_service.dart';
import 'session_store.dart';

class BackgroundTrackingService extends ChangeNotifier {
  BackgroundTrackingService({
    required LocationService locationService,
    required TrackingRepository trackingRepository,
    required SessionStore sessionStore,
    required LocalDatabase localDatabase,
  }) : _locationService = locationService,
       _trackingRepository = trackingRepository,
       _sessionStore = sessionStore,
       _localDatabase = localDatabase {
    _sessionStore.addListener(_sessionChanged);
  }

  static const _channel = MethodChannel('com.rutasapp.mobile_driver/tracking');

  final LocationService _locationService;
  final TrackingRepository _trackingRepository;
  final SessionStore _sessionStore;
  final LocalDatabase _localDatabase;
  StreamSubscription? _subscription;
  Timer? _retryTimer;
  Future<void>? _startInFlight;
  LocalTrackingSession? _session;
  bool _starting = false;
  String? _lastError;
  String? _platformLimitation = Platform.isIOS
      ? 'iOS no puede garantizar tracking después de un cierre forzado.'
      : null;
  bool _backgroundCapable = false;
  bool _permissionsPrepared = false;
  LocationPoint? _lastLocation;
  List<LocationPoint> _route = const [];

  bool get isTracking => _subscription != null;
  bool get blocksPresenceTracking => _starting || _session != null;
  String? get lastError => _lastError;
  String? get platformLimitation => _platformLimitation;
  String? get serviceId => _session?.serviceId;
  LocationPoint? get lastLocation => _lastLocation;
  List<LocationPoint> get route => List<LocationPoint>.unmodifiable(_route);

  Future<void> Function()? onPositionPersisted;
  Future<void> Function()? onTrackingStarting;

  Future<void> prepareForStart() async {
    _lastError = null;
    final permission = await _locationService.prepareContinuousTracking();
    _backgroundCapable = permission.backgroundCapable;
    if (Platform.isAndroid) {
      final notificationGranted = await _requestAndroidPermission(
        'requestNotificationPermission',
      );
      final backgroundGranted = await _requestAndroidPermission(
        'requestBackgroundLocationPermission',
      );
      _backgroundCapable = backgroundGranted;
      // Exencion del ahorro de bateria. Los permisos de arriba autorizan a
      // rastrear; este es el que evita que el sistema mate la app mientras lo
      // hace. Se ofrece una sola vez: si ya esta exenta, el nativo responde sin
      // abrir nada.
      final exenta = await _requestAndroidPermission(
        'isIgnoringBatteryOptimizations',
      );
      if (!exenta) {
        await _requestAndroidPermission('requestIgnoreBatteryOptimizations');
      }
      if (!notificationGranted) {
        _platformLimitation =
            'Android no mostrará la notificación; el sistema puede limitar el tracking.';
      } else if (!backgroundGranted) {
        _platformLimitation =
            'El permiso actual puede limitar el tracking fuera de la app.';
      }
    } else if (Platform.isIOS && !_backgroundCapable) {
      _platformLimitation =
          'iOS necesita permiso “Siempre” para continuar en segundo plano.';
      notifyListeners();
      throw const LocationFailure(
        'Concede ubicación “Siempre” antes de iniciar el servicio.',
      );
    } else if (Platform.isIOS) {
      _platformLimitation =
          'iOS no puede garantizar tracking después de un cierre forzado.';
    }
    _permissionsPrepared = true;
    notifyListeners();
  }

  Future<void> start(
    LocalTrackingSession session, {
    bool requestPermission = true,
  }) {
    final existing = _startInFlight;
    if (existing != null) return existing;
    final start = _start(session, requestPermission: requestPermission);
    _startInFlight = start;
    return start.whenComplete(() {
      if (identical(_startInFlight, start)) _startInFlight = null;
    });
  }

  Future<void> _start(
    LocalTrackingSession session, {
    required bool requestPermission,
  }) async {
    if (_session?.localId == session.localId &&
        _subscription != null &&
        _samePolicy(_session!.policy, session.policy)) {
      return;
    }
    _starting = true;
    notifyListeners();
    final permissionsPrepared = _permissionsPrepared;
    final preparedLimitation = _platformLimitation;
    try {
      await onTrackingStarting?.call();
      await stopCapture(preserveStarting: true);
      _permissionsPrepared = permissionsPrepared;
      _lastError = null;
      _platformLimitation = preparedLimitation;
      if (requestPermission && !_permissionsPrepared) {
        await prepareForStart();
      }
      final permission = await _locationService.permissionStatus();
      _backgroundCapable = permission.backgroundCapable;
      if (!_backgroundCapable) {
        _platformLimitation = Platform.isIOS
            ? 'iOS necesita permiso “Siempre” para continuar en segundo plano.'
            : 'El permiso actual puede limitar el tracking fuera de la app.';
      } else if (Platform.isIOS) {
        _platformLimitation =
            'iOS no puede garantizar tracking después de un cierre forzado.';
      }
      _session = session;
      final stream = await _locationService.positionStream(session.policy);
      _route = await _trackingRepository.positionsForService(session.serviceId);
      _lastLocation = _route.isEmpty ? null : _route.last;
      _subscription = stream.listen(
        (point) => unawaited(_persist(point)),
        onError: (Object error, StackTrace stackTrace) {
          _trackingInterrupted(error);
        },
        onDone: () => _trackingInterrupted(),
        cancelOnError: false,
      );
      _retryTimer?.cancel();
      _retryTimer = null;
      await _setNativeSessionState(active: true, serviceId: session.serviceId);
    } on Object catch (error) {
      _lastError = error is AppFailure
          ? error.message
          : 'No se pudo activar el seguimiento.';
      notifyListeners();
      rethrow;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> recoverActiveSession() async {
    if (!_sessionStore.hasOperationalSession) return;
    try {
      final session = await _trackingRepository.activeSession();
      if (session == null) {
        _session = null;
        return;
      }
      await start(session, requestPermission: false);
    } catch (_) {
      _lastError ??=
          'Hay una sesión pendiente. Abre permisos y reactiva el tracking.';
      notifyListeners();
    }
  }

  Future<void> recordLocation(LocationPoint point) async {
    if (_session == null) {
      throw const StorageFailure('No hay una sesión de seguimiento activa.');
    }
    await _persist(point);
  }

  Future<void> _persist(LocationPoint point) async {
    try {
      await _trackingRepository.persist(point);
      _lastLocation = point;
      final route = [..._route, point];
      _route = route.length <= 2000
          ? route
          : route.sublist(route.length - 2000);
      notifyListeners();
      final sync = onPositionPersisted;
      if (sync != null) unawaited(sync());
    } on Object catch (error) {
      _lastError = error is AppFailure
          ? error.message
          : 'No se pudo guardar una posición localmente.';
      notifyListeners();
    }
  }

  Future<void> stopCapture({bool preserveStarting = false}) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _session = null;
    _lastLocation = null;
    _route = const [];
    _permissionsPrepared = false;
    if (!preserveStarting) _starting = false;
    await _setNativeSessionState(active: false);
    notifyListeners();
  }

  void _trackingInterrupted([Object? error]) {
    final subscription = _subscription;
    if (subscription == null) return;
    _subscription = null;
    unawaited(subscription.cancel());
    _lastError = error is AppFailure
        ? error.message
        : error == null
        ? 'El seguimiento GPS se detuvo inesperadamente.'
        : 'El seguimiento se interrumpió: $error';
    // La sesión sigue activa: un error temporal del proveedor no debe borrar el
    // marcador nativo ni dejar el recorrido detenido hasta una apertura manual.
    _scheduleRetry();
    notifyListeners();
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive == true || !_sessionStore.hasOperationalSession) {
      return;
    }
    _retryTimer = Timer(const Duration(seconds: 10), () {
      _retryTimer = null;
      unawaited(() async {
        try {
          await recoverActiveSession();
        } finally {
          if (!isTracking && _session != null) _scheduleRetry();
        }
      }());
    });
  }

  Future<void> _setNativeSessionState({
    required bool active,
    String? serviceId,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSessionState', {
        'active': active,
        'serviceId': serviceId,
      });
    } on MissingPluginException {
      // Unit/widget environments do not register the Android channel.
    }
  }

  Future<bool> _requestAndroidPermission(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  bool _samePolicy(TrackingPolicy first, TrackingPolicy second) {
    return first.intervalSeconds == second.intervalSeconds &&
        first.distanceFilterMeters == second.distanceFilterMeters &&
        first.batchSize == second.batchSize;
  }

  void _sessionChanged() {
    if (_sessionStore.hasSession) return;
    final session = _session;
    if (session == null) return;
    unawaited(() async {
      await _localDatabase.closeTrackingSession(
        session.ownerUserId,
        session.localId,
      );
      await stopCapture();
    }());
  }

  @override
  void dispose() {
    _sessionStore.removeListener(_sessionChanged);
    _retryTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
