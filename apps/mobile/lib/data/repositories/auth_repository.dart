import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/auth_session.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';
import '../services/location_service.dart';
import '../services/push_service.dart';
import '../services/session_store.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required SessionStore sessionStore,
    required LocalDatabase localDatabase,
    DeviceInfoPlugin? deviceInfo,
    PushService? pushService,
    LocationService? locationService,
  }) : _apiClient = apiClient,
       _sessionStore = sessionStore,
       _localDatabase = localDatabase,
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _pushService = pushService,
       _locationService = locationService;

  final PushService? _pushService;
  final LocationService? _locationService;
  final ApiClient _apiClient;
  final SessionStore _sessionStore;
  final LocalDatabase _localDatabase;
  final DeviceInfoPlugin _deviceInfo;
  Future<String>? _deviceRegistrationInFlight;

  UserProfile? get currentUser => _sessionStore.user;

  Future<void> requestNotificationPermission() {
    return _pushService?.registrarTrasIniciarSesion() ?? Future<void>.value();
  }

  /// Pide el permiso de ubicación al iniciar sesión.
  ///
  /// Al conductor se le pide el permiso continuo, que es el que permite seguir
  /// enviando posiciones con la pantalla bloqueada. Al resto alcanza con el de
  /// uso puntual, para el botón de "usar mi ubicación".
  ///
  /// Nunca interrumpe el inicio de sesión: si el permiso se rechaza, la app
  /// funciona igual y lo volverá a pedir cuando haga falta.
  Future<void> _pedirPermisoDeUbicacion(String role) async {
    final locationService = _locationService;
    if (locationService == null) return;
    try {
      if (role == 'DRIVER') {
        await locationService.prepareContinuousTracking();
      } else {
        await locationService.currentLocation();
      }
    } catch (_) {
      // Permiso rechazado o GPS apagado: no bloquea el acceso.
    }
  }

  Future<DriverProfileDetails> driverProfile() async {
    final response = await _apiClient.getJson('/mobile/profile');
    final driver = response['driver'];
    if (driver is! Map<String, dynamic>) {
      throw const ApiFailure(
        'No se pudo cargar el perfil del conductor.',
        kind: AppFailureKind.validation,
      );
    }
    return DriverProfileDetails.fromJson(driver);
  }

  Future<AuthSession> login(String email, String password) async {
    final response = await _apiClient.postJson('/auth/login', {
      'emailOrUsername': email,
      'password': password,
    }, authenticated: false);
    final AuthSession session;
    try {
      session = AuthSession.fromJson(response);
    } catch (_) {
      throw const ApiFailure(
        'La respuesta de inicio de sesión está incompleta.',
        kind: AppFailureKind.validation,
      );
    }
    await _localDatabase.closeAllActiveTrackingSessions(session.user.id);
    await _sessionStore.saveSession(session);
    // Los avisos push son para todos los roles, no sólo conductores. Si el
    // registro falla, la sesión sigue siendo válida: se pierde el aviso, no el
    // acceso.
    unawaited(
      _pushService?.registrarTrasIniciarSesion() ?? Future<void>.value(),
    );
    // El permiso de ubicación se pide acá y no cuando hace falta por primera
    // vez: un conductor que se marca disponible sin haberlo concedido no
    // transmite su posición y desaparece del mapa sin ningún aviso.
    unawaited(_pedirPermisoDeUbicacion(session.user.role));
    // Para DRIVER, App detecta que falta serverDeviceId y muestra su pantalla
    // de registro con reintento. No se bloquea ni revierte un login válido.
    return session;
  }

  Future<String> ensureDeviceRegistered() {
    final registered = _sessionStore.serverDeviceId;
    if (registered != null && registered.isNotEmpty) {
      return Future.value(registered);
    }
    final existing = _deviceRegistrationInFlight;
    if (existing != null) return existing;
    final registration = _registerDevice();
    _deviceRegistrationInFlight = registration;
    return registration.whenComplete(() {
      if (identical(_deviceRegistrationInFlight, registration)) {
        _deviceRegistrationInFlight = null;
      }
    });
  }

  Future<String> _registerDevice() async {
    final package = await PackageInfo.fromPlatform();
    final response = await _apiClient.postJson('/devices/register', {
      'installationId': _sessionStore.installationId,
      'platform': Platform.operatingSystem,
      'model': await _deviceModel(),
      'appVersion': '${package.version}+${package.buildNumber}',
      'deviceFingerprint':
          '${Platform.operatingSystem}-${_sessionStore.installationId}',
    });
    final data = response['data'];
    final root = data is Map<String, dynamic> ? data : response;
    final device = root['device'];
    final serverDeviceId =
        root['deviceId'] as String? ??
        root['id'] as String? ??
        (device is Map<String, dynamic> ? device['id'] as String? : null);
    if (serverDeviceId == null || serverDeviceId.isEmpty) {
      throw const ApiFailure(
        'El registro del dispositivo no devolvió serverDeviceId.',
        kind: AppFailureKind.validation,
      );
    }
    await _sessionStore.saveServerDeviceId(serverDeviceId);
    return serverDeviceId;
  }

  Future<String> _deviceModel() async {
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return info.model;
    }
    if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return info.utsname.machine;
    }
    final info = await _deviceInfo.deviceInfo;
    return info.data['model']?.toString() ?? Platform.localHostname;
  }

  Future<void> logout() async {
    // Antes de cerrar: si no se da de baja el token, este teléfono seguiría
    // recibiendo avisos de una cuenta que ya no lo usa.
    try {
      try {
        await _pushService?.darDeBajaAlCerrarSesion();
      } catch (_) {
        // El teardown remoto no debe impedir borrar credenciales locales.
      }
      try {
        await _apiClient.postJson('/auth/logout', const {});
      } catch (_) {
        // Pending operational data stays owner-scoped. Credentials are always
        // cleared locally, even when server revocation must complete later.
      }
    } catch (_) {
      // Conserva el finally como última barrera ante errores de plugins.
    } finally {
      await _sessionStore.clear();
    }
  }
}
