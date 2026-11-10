import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/location_point.dart';
import '../../domain/models/tracking_session.dart';

class LocationFailure extends AppFailure {
  const LocationFailure(super.message, {super.retryable = false})
    : super(kind: AppFailureKind.location);
}

class TrackingPermissionStatus {
  const TrackingPermissionStatus({
    required this.permission,
    required this.backgroundCapable,
  });

  final LocationPermission permission;
  final bool backgroundCapable;
}

class LocationService {
  double distanceBetween(
    LocationPoint location,
    double latitude,
    double longitude,
  ) {
    return Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      latitude,
      longitude,
    );
  }

  Future<LocationPoint> currentLocation() async {
    await _ensureServiceAndPermission(requestPermission: true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return _point(position);
    } on TimeoutException {
      throw const LocationFailure(
        'No se obtuvo una posición GPS dentro del tiempo esperado.',
        retryable: true,
      );
    } on LocationServiceDisabledException {
      throw const LocationFailure(
        'Activa la ubicación del teléfono para continuar.',
      );
    } on LocationFailure {
      rethrow;
    } catch (_) {
      throw const LocationFailure(
        'El GPS no está disponible en este momento.',
        retryable: true,
      );
    }
  }

  Future<TrackingPermissionStatus> prepareContinuousTracking() async {
    final permission = await _ensureServiceAndPermission(
      requestPermission: true,
    );
    return TrackingPermissionStatus(
      permission: permission,
      backgroundCapable: permission == LocationPermission.always,
    );
  }

  Future<TrackingPermissionStatus> permissionStatus() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return const TrackingPermissionStatus(
        permission: LocationPermission.denied,
        backgroundCapable: false,
      );
    }
    final permission = await Geolocator.checkPermission();
    return TrackingPermissionStatus(
      permission: permission,
      backgroundCapable: permission == LocationPermission.always,
    );
  }

  Future<Stream<LocationPoint>> positionStream(
    TrackingPolicy policy, {
    bool presenceMode = false,
  }) async {
    await _ensureServiceAndPermission(requestPermission: false);
    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: policy.distanceFilterMeters,
        intervalDuration: Duration(seconds: policy.intervalSeconds),
        foregroundNotificationConfig: presenceMode
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Disponible para asignación',
                notificationText:
                    'Rutas Control comparte tu ubicación mientras estás disponible.',
                notificationChannelName: 'Disponibilidad de conductores',
                enableWakeLock: true,
                setOngoing: true,
              )
            : const ForegroundNotificationConfig(
                notificationTitle:
                    'Rutas Control está registrando el recorrido',
                notificationText:
                    'La ubicación se guarda para el servicio de transporte activo.',
                notificationChannelName: 'Seguimiento de servicios',
                enableWakeLock: true,
                setOngoing: true,
              ),
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: policy.distanceFilterMeters,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: policy.distanceFilterMeters,
      );
    }

    return Geolocator.getPositionStream(locationSettings: settings).map(_point);
  }

  /// ¿Está encendida la ubicación del teléfono? Distingue el GPS apagado del
  /// permiso denegado, que se resuelven en pantallas de ajustes distintas.
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Ajustes de ubicación del sistema, para encender el GPS.
  Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  /// Ficha de la app en Ajustes, único sitio donde se puede devolver un permiso
  /// que el usuario bloqueó: una vez denegado para siempre, el sistema ya no
  /// vuelve a mostrar el diálogo por más que la app lo pida.
  Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }

  Future<LocationPermission> _ensureServiceAndPermission({
    required bool requestPermission,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationFailure(
        'La ubicación está desactivada. No se registró ninguna coordenada.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'El permiso de ubicación está bloqueado. Habilítalo en Ajustes.',
      );
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationFailure(
        'Se necesita permiso de ubicación para esta acción.',
      );
    }
    return permission;
  }

  LocationPoint _point(Position position) {
    return LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      altitude: position.altitude,
      isMocked: position.isMocked,
      provider: Platform.isAndroid
          ? 'android_location_provider'
          : Platform.isIOS
          ? 'core_location'
          : Platform.operatingSystem,
      capturedAt: position.timestamp.toUtc(),
    );
  }
}
