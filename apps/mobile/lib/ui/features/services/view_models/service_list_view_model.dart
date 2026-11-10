import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_presence_repository.dart';
import '../../../../data/repositories/service_event_repository.dart';
import '../../../../data/repositories/notification_repository.dart';
import '../../../../data/repositories/service_repository.dart';
import '../../../../data/repositories/tracking_repository.dart';
import '../../../../data/services/background_tracking_service.dart';
import '../../../../data/services/location_service.dart';
import '../../../../data/services/road_routing_service.dart';
import '../../../../data/services/sync_coordinator.dart';
import '../../../../domain/models/auth_session.dart';
import '../../../../domain/models/in_app_notification.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../domain/models/transport_service.dart';

class ServiceListViewModel extends ChangeNotifier {
  ServiceListViewModel({
    required ServiceRepository serviceRepository,
    required ServiceEventRepository eventRepository,
    required AuthRepository authRepository,
    required SyncCoordinator syncCoordinator,
    required BackgroundTrackingService backgroundTrackingService,
    required TrackingRepository trackingRepository,
    required NotificationRepository notificationRepository,
    required DriverPresenceRepository driverPresenceRepository,
    required LocationService locationService,
    required RoadRoutingService roadRoutingService,
  }) : _serviceRepository = serviceRepository,
       _eventRepository = eventRepository,
       _authRepository = authRepository,
       _syncCoordinator = syncCoordinator,
       _backgroundTrackingService = backgroundTrackingService,
       _trackingRepository = trackingRepository,
       _notificationRepository = notificationRepository,
       _driverPresenceRepository = driverPresenceRepository,
       _locationService = locationService,
       _roadRoutingService = roadRoutingService {
    _syncCoordinator.addListener(_syncChanged);
    _backgroundTrackingService.addListener(_trackingChanged);
    _driverPresenceRepository.addListener(_presenceChanged);
  }

  final ServiceRepository _serviceRepository;
  final ServiceEventRepository _eventRepository;
  final AuthRepository _authRepository;
  final SyncCoordinator _syncCoordinator;
  final BackgroundTrackingService _backgroundTrackingService;
  final TrackingRepository _trackingRepository;
  final NotificationRepository _notificationRepository;
  final DriverPresenceRepository _driverPresenceRepository;
  final LocationService _locationService;
  final RoadRoutingService _roadRoutingService;

  bool _isLoading = false;
  String? _errorMessage;
  String? _warningMessage;
  List<TransportService> _services = const [];
  int _pendingCount = 0;
  int _deadLetterCount = 0;
  bool _loadingNotifications = false;
  String? _notificationError;
  List<InAppNotification> _notifications = const [];
  DriverProfileDetails? _driverProfile;
  bool _emergencySending = false;
  String? _emergencyMessage;
  bool _dedicatedActionBusy = false;
  String? _dedicatedActionMessage;
  String? _dedicatedActionError;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _friendlyDriverError(
    _warningMessage ??
        _backgroundTrackingService.lastError ??
        _syncCoordinator.lastError,
  );
  List<TransportService> get services => _services;
  int get pendingCount => _pendingCount;
  int get deadLetterCount => _deadLetterCount;
  bool get isTracking => _backgroundTrackingService.isTracking;
  String? get trackingLimitation =>
      _backgroundTrackingService.platformLimitation;
  String get userName => _authRepository.currentUser?.fullName ?? 'Conductor';
  UserProfile? get currentUser => _authRepository.currentUser;
  List<InAppNotification> get notifications => _notifications;
  int get unreadNotificationCount =>
      _notifications.where((notification) => !notification.read).length;
  String? get notificationError => _notificationError;
  DriverProfileDetails? get driverProfile => _driverProfile;
  bool get emergencySending => _emergencySending;
  String? get emergencyMessage => _emergencyMessage;
  bool get isDedicatedDriver => _driverProfile?.isDedicated ?? false;
  bool get dedicatedActionBusy => _dedicatedActionBusy;
  String? get dedicatedActionMessage => _dedicatedActionMessage;
  String? get dedicatedActionError => _dedicatedActionError;
  TransportService? get activeDedicatedService {
    for (final service in _services) {
      if (service.hasActiveDedicatedDuty) return service;
    }
    return null;
  }

  bool get canStartDedicatedDuty =>
      isDedicatedDriver && activeDedicatedService == null;
  String? get trackingServiceId =>
      _backgroundTrackingService.serviceId ?? _activeService?.id;
  LocationPoint? get lastTrackingLocation =>
      _backgroundTrackingService.lastLocation ??
      (_activeService?.actualRoute.isEmpty ?? true
          ? null
          : _activeService!.actualRoute.last);
  LocationPoint? get driverLocation =>
      lastTrackingLocation ?? _driverPresenceRepository.lastLocation;
  List<LocationPoint> get localTrackingRoute =>
      _backgroundTrackingService.route;
  bool get presenceAvailable => _driverPresenceRepository.available;
  bool get presenceUpdating => _driverPresenceRepository.updating;
  bool get isSharingPresenceLocation =>
      _driverPresenceRepository.isSharingLocation;
  bool get presencePausedForRoute => _driverPresenceRepository.pausedForRoute;
  String? get presenceError =>
      _friendlyDriverError(_driverPresenceRepository.lastError);
  DateTime? get lastPresenceUpdate => _driverPresenceRepository.lastSentAt;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await Future.wait([
        _driverPresenceRepository.load(),
        _loadDriverProfile(),
      ]);
      await _eventRepository.syncPending();
      final assigned = await _serviceRepository.assignedServices();
      _services = isDedicatedDriver
          ? assigned.where((service) => service.isDedicated).toList()
          : assigned;
      final activeSession = await _trackingRepository.restoreActiveSession(
        _services,
      );
      if (activeSession == null) {
        if (_backgroundTrackingService.serviceId != null) {
          await _backgroundTrackingService.stopCapture();
        }
      } else {
        await _backgroundTrackingService.recoverActiveSession();
      }
      _warningMessage = _serviceRepository.lastWarning;
      await _refreshSyncState();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sync() => load();

  Future<void> recoverAfterResume() async {
    try {
      await _backgroundTrackingService.recoverActiveSession();
      await _syncCoordinator.syncNow();
    } catch (error) {
      _warningMessage = error.toString();
      notifyListeners();
    }
  }

  Future<bool> setPresenceAvailable(bool value) {
    return _driverPresenceRepository.setAvailable(value);
  }

  /// Lleva al conductor a la pantalla de ajustes que corresponde: la del
  /// sistema si el GPS está apagado, y la de la app si lo que falta es el
  /// permiso. Se decide al pulsar y no al mostrar el error, para no razonar
  /// sobre un estado que pudo cambiar mientras el aviso estaba en pantalla.
  Future<void> openLocationSettings() async {
    final enabled = await _locationService.isLocationServiceEnabled();
    if (enabled) {
      await _locationService.openAppSettings();
      return;
    }
    await _locationService.openLocationSettings();
  }

  Future<TransportService?> startDedicatedDuty() async {
    if (_dedicatedActionBusy) return null;
    if (!isDedicatedDriver) {
      _dedicatedActionError =
          'El inicio dedicado no está habilitado para este conductor.';
      notifyListeners();
      return null;
    }
    final active = activeDedicatedService;
    if (active != null) return active;

    _dedicatedActionBusy = true;
    _dedicatedActionError = null;
    _dedicatedActionMessage = null;
    notifyListeners();
    TransportService? acceptedService;
    try {
      await _backgroundTrackingService.prepareForStart();
      final location = await _locationService.currentLocation();
      final address = await _addressFor(location);
      final result = await _serviceRepository.startDedicatedService(
        clientWaypointId: const Uuid().v4(),
        location: location,
        address: address,
      );
      acceptedService = result.service;
      _mergeService(result.service);
      notifyListeners();

      final localSession = await _trackingRepository.restoreActiveSession([
        result.service,
      ]);
      if (localSession == null) {
        throw const AppFailure(
          'El servicio inició, pero no devolvió una sesión de seguimiento.',
          kind: AppFailureKind.validation,
        );
      }
      await _backgroundTrackingService.start(localSession);
      await _backgroundTrackingService.recordLocation(location);
      await _syncCoordinator.syncNow();
      _dedicatedActionMessage = result.duplicate
          ? 'El servicio ya estaba iniciado. Se reactivó el seguimiento GPS.'
          : 'Servicio iniciado. El recorrido GPS ya se está registrando.';
      return result.service;
    } catch (error) {
      _dedicatedActionError = acceptedService == null
          ? _friendlyDriverError(error.toString())
          : 'El servicio inició, pero el seguimiento GPS necesita atención: $error';
      return acceptedService;
    } finally {
      _dedicatedActionBusy = false;
      notifyListeners();
    }
  }

  void clearDedicatedActionFeedback() {
    _dedicatedActionMessage = null;
    _dedicatedActionError = null;
  }

  Future<bool> sendEmergency() async {
    if (_emergencySending) return false;
    _emergencySending = true;
    _emergencyMessage = null;
    notifyListeners();
    try {
      await _notificationRepository.sendEmergency(
        serviceId: _activeService?.id,
      );
      _emergencyMessage =
          'Alerta enviada. Un administrador se pondrá en contacto contigo.';
      return true;
    } catch (_) {
      _emergencyMessage =
          'No se pudo enviar la alerta. Intenta nuevamente o llama a emergencias.';
      return false;
    } finally {
      _emergencySending = false;
      notifyListeners();
    }
  }

  TransportService? get _activeService {
    for (final service in _services) {
      if (service.trackingSession?.isActive ?? false) return service;
    }
    return null;
  }

  void _mergeService(TransportService service) {
    _services = [
      service,
      for (final current in _services)
        if (current.id != service.id) current,
    ];
  }

  Future<String> _addressFor(LocationPoint location) async {
    try {
      final address = await _roadRoutingService.reverseGeocode(
        LatLng(location.latitude, location.longitude),
      );
      if (address.trim().isNotEmpty) return address.trim();
    } catch (_) {
      // La coordenada sigue siendo válida aunque Google no resuelva la calle.
    }
    return 'Ubicación GPS ${location.latitude.toStringAsFixed(6)}, '
        '${location.longitude.toStringAsFixed(6)}';
  }

  Future<void> _loadDriverProfile() async {
    try {
      _driverProfile = await _authRepository.driverProfile();
    } catch (_) {
      _driverProfile = null;
    }
  }

  Future<void> loadNotifications() async {
    if (_loadingNotifications) return;
    _loadingNotifications = true;
    try {
      _notifications = await _notificationRepository.notifications();
      _notificationError = null;
    } catch (error) {
      _notificationError = error.toString();
    } finally {
      _loadingNotifications = false;
      notifyListeners();
    }
  }

  Future<String?> openNotification(InAppNotification notification) async {
    try {
      if (!notification.read) {
        await _notificationRepository.markRead(notification.id);
        _notifications = [
          for (final item in _notifications)
            if (item.id == notification.id) item.copyWith(read: true) else item,
        ];
      }
      _notificationError = null;
      notifyListeners();
      return notification.serviceId;
    } catch (error) {
      _notificationError = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> _refreshSyncState() async {
    _pendingCount = await _eventRepository.pendingCount();
    _deadLetterCount = _syncCoordinator.health.deadLetterCount;
  }

  Future<void> logout() async {
    await _driverPresenceRepository.pause();
    final wasTracking = _backgroundTrackingService.isTracking;
    if (wasTracking) await _backgroundTrackingService.stopCapture();
    await _syncCoordinator.syncNow();
    await _refreshSyncState();
    if (_pendingCount > 0 || _deadLetterCount > 0) {
      _warningMessage =
          'No se cerró la sesión: resuelve o sincroniza los datos operativos pendientes.';
      if (wasTracking) {
        await _backgroundTrackingService.recoverActiveSession();
      }
      await _driverPresenceRepository.resumeIfAvailable();
      notifyListeners();
      return;
    }
    await _trackingRepository.closeActiveSession();
    await _driverPresenceRepository.disableForLogout();
    await _authRepository.logout();
  }

  void _syncChanged() {
    _pendingCount = _syncCoordinator.health.pendingCount;
    _deadLetterCount = _syncCoordinator.health.deadLetterCount;
    notifyListeners();
  }

  void _trackingChanged() => notifyListeners();

  void _presenceChanged() => notifyListeners();

  @override
  void dispose() {
    _syncCoordinator.removeListener(_syncChanged);
    _backgroundTrackingService.removeListener(_trackingChanged);
    _driverPresenceRepository.removeListener(_presenceChanged);
    super.dispose();
  }
}

String? _friendlyDriverError(String? message) {
  if (message == null) return null;
  if (message.toLowerCase().contains('request body is invalid')) {
    return 'No pudimos sincronizar una ubicación anterior. La app volverá a intentarlo automáticamente.';
  }
  return message;
}
