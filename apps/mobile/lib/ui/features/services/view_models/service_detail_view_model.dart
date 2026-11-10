import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/repositories/evidence_repository.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/service_event_repository.dart';
import '../../../../data/repositories/service_repository.dart';
import '../../../../data/repositories/tracking_repository.dart';
import '../../../../data/services/background_tracking_service.dart';
import '../../../../data/services/location_service.dart';
import '../../../../data/services/road_routing_service.dart';
import '../../../../data/services/sync_coordinator.dart';
import '../../../../domain/models/auth_session.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../domain/models/transport_service.dart';
import '../../../../core/errors/app_failure.dart';

class ServiceDetailViewModel extends ChangeNotifier {
  ServiceDetailViewModel({
    required String serviceId,
    required ServiceRepository serviceRepository,
    required ServiceEventRepository eventRepository,
    required EvidenceRepository evidenceRepository,
    required LocationService locationService,
    required BackgroundTrackingService backgroundTrackingService,
    required SyncCoordinator syncCoordinator,
    required AuthRepository authRepository,
    required TrackingRepository trackingRepository,
    required RoadRoutingService roadRoutingService,
    bool dedicatedDriverHint = false,
  }) : _serviceId = serviceId,
       _serviceRepository = serviceRepository,
       _eventRepository = eventRepository,
       _evidenceRepository = evidenceRepository,
       _locationService = locationService,
       _backgroundTrackingService = backgroundTrackingService,
       _syncCoordinator = syncCoordinator,
       _authRepository = authRepository,
       _trackingRepository = trackingRepository,
       _roadRoutingService = roadRoutingService,
       _dedicatedDriverHint = dedicatedDriverHint {
    _backgroundTrackingService.addListener(_trackingChanged);
    _syncCoordinator.addListener(_syncChanged);
  }

  final String _serviceId;
  final ServiceRepository _serviceRepository;
  final ServiceEventRepository _eventRepository;
  final EvidenceRepository _evidenceRepository;
  final LocationService _locationService;
  final BackgroundTrackingService _backgroundTrackingService;
  final SyncCoordinator _syncCoordinator;
  final AuthRepository _authRepository;
  final TrackingRepository _trackingRepository;
  final RoadRoutingService _roadRoutingService;
  final bool _dedicatedDriverHint;

  bool _isLoading = false;
  bool _isRegisteringDedicatedStop = false;
  String? _message;
  String? _errorMessage;
  TransportService? _service;
  int _pendingCount = 0;
  bool _hasPendingCommand = false;
  bool _hasBlockingFailure = false;
  bool _routeStarted = false;
  bool _refreshingAfterSync = false;
  bool _disposed = false;
  DriverProfileDetails? _driverProfile;

  bool get isLoading => _isLoading;
  bool get isRegisteringDedicatedStop => _isRegisteringDedicatedStop;
  String? get message => _message;
  String? get errorMessage => _errorMessage;
  TransportService? get service => _service;
  int get pendingCount => _pendingCount;
  bool get hasPendingCommand => _hasPendingCommand;
  bool get hasBlockingFailure => _hasBlockingFailure;
  bool get isTracking => _backgroundTrackingService.isTracking;
  String? get trackingError => _backgroundTrackingService.lastError;
  String? get trackingLimitation =>
      _backgroundTrackingService.platformLimitation;
  String? get syncError {
    final error = _syncCoordinator.lastError;
    if (error == null) return null;
    if (error.contains('Error HTTP 5')) {
      return 'No pudimos sincronizar la última ubicación. Se reintentará automáticamente.';
    }
    return error;
  }

  bool get routeStarted => _routeStarted;
  bool get isRouteActive =>
      _backgroundTrackingService.isTracking ||
      (_service?.hasActiveDedicatedDuty ?? false) ||
      const {
        'EN_SERVICIO',
        // Compatibilidad con apps que aún no se han actualizado.
        'INICIADO',
        'EN_RECORRIDO',
        'EN_RUTA',
      }.contains(_service?.currentStatus);
  bool get isDedicatedDuty =>
      (_dedicatedDriverHint || (_driverProfile?.isDedicated ?? false)) &&
      (_service?.isDedicated ?? false);
  bool get isDedicatedDutyActive =>
      isDedicatedDuty && (_service?.hasActiveDedicatedDuty ?? false);
  List<DedicatedWaypoint> get dedicatedStops =>
      _service?.dedicatedStops ?? const [];
  bool get canBeginRoute {
    final service = _service;
    if (service == null || _backgroundTrackingService.isTracking) return false;
    return service.allowedActions.any(_preStartActions.contains);
  }

  bool isPreStartAction(ServiceAction action) =>
      _preStartActions.contains(action);

  /// Lo único previo al viaje. Antes eran cuatro pasos encadenados; con tres
  /// estados el conductor pulsa una vez y ya está en servicio.
  static const _preStartActions = {ServiceAction.start};

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final profileLoad = _loadDriverProfile();
      _service = await _serviceRepository.serviceDetail(_serviceId);
      await profileLoad;
      await _refreshPendingState();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> executeSimple(ServiceAction action) async {
    final needsLocation = switch (action) {
      ServiceAction.finish || ServiceAction.suspend => false,
      _ => true,
    };
    await _execute(action, needsLocation: needsLocation);
  }

  Future<void> retryTracking() async {
    await _withAction(() async {
      await _backgroundTrackingService.prepareForStart();
      await _backgroundTrackingService.recoverActiveSession();
      if (!_backgroundTrackingService.isTracking) {
        throw AppFailure(
          _backgroundTrackingService.lastError ??
              'No se pudo reactivar el seguimiento GPS.',
          kind: AppFailureKind.location,
          retryable: true,
        );
      }
    });
  }

  Future<void> registerDedicatedStop() async {
    if (_isLoading) return;
    _isRegisteringDedicatedStop = true;
    notifyListeners();
    try {
      await _withAction(() async {
        final service = _requireDedicatedService(active: true);
        await _ensureDedicatedTracking();
        final location = await _locationService.currentLocation();
        final address = await _addressFor(location);
        final result = await _serviceRepository.registerDedicatedStop(
          service: service,
          clientWaypointId: const Uuid().v4(),
          location: location,
          address: address,
        );
        _service = result.service;
        await _recordDedicatedLocation(location, service.id);
        _message = result.duplicate
            ? 'Esta parada ya estaba registrada.'
            : 'Parada registrada en $address.';
        await _reloadDedicatedService();
      });
    } finally {
      _isRegisteringDedicatedStop = false;
      notifyListeners();
    }
  }

  Future<void> finishDedicatedDuty() async {
    if (_isLoading) return;
    await _withAction(() async {
      final service = _requireDedicatedService(active: true);
      await _ensureDedicatedTracking();
      final location = await _locationService.currentLocation();
      final address = await _addressFor(location);
      await _recordDedicatedLocation(location, service.id);
      await _syncCoordinator.syncNow();
      final result = await _serviceRepository.finishDedicatedService(
        service: service,
        clientWaypointId: const Uuid().v4(),
        location: location,
        address: address,
      );
      _service = result.service;
      await _trackingRepository.closeActiveSession();
      await _backgroundTrackingService.stopCapture();
      _message = result.duplicate
          ? 'El servicio ya estaba finalizado.'
          : 'Servicio finalizado correctamente.';
      await _reloadDedicatedService();
    });
  }

  Future<void> beginRoute() async {
    await _withAction(() async {
      _routeStarted = false;
      await _reloadAfterAction();
      _verifyOwnership(_requireService());
      await _backgroundTrackingService.prepareForStart();
      final location = await _locationService.currentLocation();
      // Sin geocerca de origen: el conductor arranca desde donde esté y la
      // posición de arranque queda en el evento.
      await _completeStart(location);
      _routeStarted = true;
    });
  }

  Future<void> _completeStart(LocationPoint location) async {
    final service = _requireService();
    if (service.allowedActions.contains(ServiceAction.start)) {
      final synchronized = await _eventRepository.execute(
        service: service,
        action: ServiceAction.start,
        location: location,
      );
      _message = synchronized
          ? 'Servicio iniciado correctamente.'
          : 'Inicio guardado y pendiente de sincronización.';
      await _reloadAfterAction();
    }
    final started = isRouteActive;
    if (!started) {
      throw const AppFailure(
        'El servidor todavía no habilitó el inicio de la ruta.',
        kind: AppFailureKind.conflict,
      );
    }
    if (!_backgroundTrackingService.isTracking) {
      throw AppFailure(
        _backgroundTrackingService.lastError ??
            'El servicio inició, pero el seguimiento GPS no está activo.',
        kind: AppFailureKind.location,
        retryable: true,
      );
    }
  }

  void _verifyOwnership(TransportService service) {
    final assignmentDriverId = service.assignment?.driverId;
    final currentDriverId = _authRepository.currentUser?.driverId;
    if (assignmentDriverId != null &&
        currentDriverId != null &&
        assignmentDriverId != currentDriverId) {
      throw const AppFailure(
        'Esta ruta no está asignada al conductor autenticado.',
        kind: AppFailureKind.authorization,
      );
    }
  }

  Future<void> registerStop({required String reasonCode, String? notes}) {
    return _execute(
      ServiceAction.stop,
      needsLocation: true,
      extra: {
        'clientStopId': const Uuid().v4(),
        'reasonCode': reasonCode,
        if (notes?.trim().isNotEmpty ?? false) 'notes': notes!.trim(),
      },
    );
  }

  Future<void> reportIncident({
    required String incidentType,
    required String severity,
    required String description,
    required bool attachPhoto,
  }) async {
    await _withAction(() async {
      final service = _requireService();
      final location = await _locationService.currentLocation();
      final evidenceId = attachPhoto
          ? await _evidenceRepository.capturePhotoEvidence(service.id, location)
          : null;
      final synchronized = await _eventRepository.execute(
        service: service,
        action: ServiceAction.incident,
        location: location,
        extra: {
          'clientIncidentId': const Uuid().v4(),
          'incidentType': incidentType,
          'severity': severity,
          'description': description.trim(),
        },
        evidenceIds: evidenceId == null ? const [] : [evidenceId],
      );
      _message = synchronized
          ? 'Incidencia registrada.'
          : 'Incidencia guardada y pendiente de sincronización.';
      await _reloadAfterAction();
    });
  }

  Future<void> suspend(String reason) {
    return _execute(
      ServiceAction.suspend,
      needsLocation: false,
      extra: {'reason': reason.trim()},
    );
  }

  Future<void> _execute(
    ServiceAction action, {
    required bool needsLocation,
    Map<String, dynamic> extra = const {},
  }) async {
    await _withAction(() async {
      final service = _requireService();
      if (action == ServiceAction.start) {
        await _backgroundTrackingService.prepareForStart();
      }
      final LocationPoint? location = needsLocation
          ? await _locationService.currentLocation()
          : null;
      final synchronized = await _eventRepository.execute(
        service: service,
        action: action,
        location: location,
        extra: extra,
      );
      _message = synchronized
          ? '${action.label} registrada correctamente.'
          : '${action.label} guardada y pendiente de sincronización.';
      await _reloadAfterAction();
    });
  }

  TransportService _requireService() {
    final value = _service;
    if (value == null) throw StateError('Servicio no disponible.');
    return value;
  }

  TransportService _requireDedicatedService({required bool active}) {
    final service = _requireService();
    if (!isDedicatedDuty) {
      throw const AppFailure(
        'Este servicio no pertenece al flujo de conductor dedicado.',
        kind: AppFailureKind.authorization,
      );
    }
    if (active && !service.hasActiveDedicatedDuty) {
      throw const AppFailure(
        'No hay un servicio dedicado activo.',
        kind: AppFailureKind.conflict,
      );
    }
    return service;
  }

  Future<void> _recordDedicatedLocation(
    LocationPoint location,
    String serviceId,
  ) async {
    if (_backgroundTrackingService.serviceId != serviceId) return;
    await _backgroundTrackingService.recordLocation(location);
  }

  Future<void> _ensureDedicatedTracking() async {
    if (_backgroundTrackingService.isTracking) return;
    await _backgroundTrackingService.prepareForStart();
    await _backgroundTrackingService.recoverActiveSession();
    if (!_backgroundTrackingService.isTracking) {
      throw AppFailure(
        _backgroundTrackingService.lastError ??
            'No se pudo reactivar el seguimiento GPS.',
        kind: AppFailureKind.location,
        retryable: true,
      );
    }
  }

  Future<String> _addressFor(LocationPoint location) async {
    try {
      final address = await _roadRoutingService.reverseGeocode(
        LatLng(location.latitude, location.longitude),
      );
      if (address.trim().isNotEmpty) return address.trim();
    } catch (_) {
      // La coordenada sigue siendo utilizable si Google no resuelve la calle.
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

  Future<void> _reloadDedicatedService() async {
    try {
      final refreshed = await _serviceRepository.serviceDetail(_serviceId);
      if (refreshed != null &&
          refreshed.waypoints.length >= (_service?.waypoints.length ?? 0)) {
        _service = refreshed;
      }
    } catch (_) {
      // Conserva la respuesta aceptada del endpoint dedicado.
    }
    await _refreshPendingState();
  }

  Future<void> _reloadAfterAction() async {
    _service = await _serviceRepository.serviceDetail(_serviceId);
    await _refreshPendingState();
  }

  Future<void> _refreshPendingState() async {
    _pendingCount = await _eventRepository.pendingCount();
    _hasPendingCommand = await _eventRepository.hasPendingCommand(_serviceId);
    _hasBlockingFailure = await _eventRepository.hasDeadLetter(_serviceId);
  }

  Future<void> _withAction(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    _message = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _errorMessage = error.toString();
      try {
        _service = await _serviceRepository.serviceDetail(_serviceId);
      } catch (_) {
        // Keep the last local snapshot while the rejection remains visible.
      }
      await _refreshPendingState();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _trackingChanged() => notifyListeners();

  void _syncChanged() {
    _pendingCount = _syncCoordinator.health.pendingCount;
    if (!_refreshingAfterSync) unawaited(_refreshAfterSync());
    notifyListeners();
  }

  Future<void> _refreshAfterSync() async {
    _refreshingAfterSync = true;
    try {
      final cached = await _serviceRepository.cachedServiceDetail(_serviceId);
      if (_disposed) return;
      if (cached != null) _service = cached;
      await _refreshPendingState();
      if (!_disposed) notifyListeners();
    } finally {
      _refreshingAfterSync = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _backgroundTrackingService.removeListener(_trackingChanged);
    _syncCoordinator.removeListener(_syncChanged);
    super.dispose();
  }
}
