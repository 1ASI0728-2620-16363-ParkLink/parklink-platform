import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../data/repositories/admin_repository.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/notification_repository.dart';
import '../../../../domain/models/admin_records.dart';
import '../../../../domain/models/in_app_notification.dart';
import '../../../../domain/models/transport_service.dart';

class AdminViewModel extends ChangeNotifier {
  AdminViewModel({
    required AdminRepository adminRepository,
    required AuthRepository authRepository,
    required NotificationRepository notificationRepository,
  }) : _adminRepository = adminRepository,
       _authRepository = authRepository,
       _notificationRepository = notificationRepository;

  final AdminRepository _adminRepository;
  final AuthRepository _authRepository;
  final NotificationRepository _notificationRepository;

  bool _isLoading = false;
  String? _message;
  String? _errorMessage;
  List<TransportService> _services = const [];
  List<DriverRecord> _drivers = const [];
  List<VehicleRecord> _vehicles = const [];
  List<InvitationRecord> _invitations = const [];
  List<LiveVehicleRecord> _liveVehicles = const [];
  List<DriverLiveLocation> _liveDrivers = const [];
  String? _liveVehiclesError;
  String? _liveDriversError;
  bool _loadingLiveVehicles = false;
  bool _loadingLiveDrivers = false;
  final Set<String> _requestingDriverIds = {};
  StreamSubscription<Map<String, dynamic>>? _liveSubscription;
  StreamSubscription<Map<String, dynamic>>? _serviceSubscription;
  Timer? _liveFallbackTimer;
  Timer? _liveReconnectTimer;
  Timer? _serviceReconnectTimer;
  Timer? _notificationTimer;
  bool _liveUpdatesEnabled = false;
  int _liveReconnectAttempt = 0;
  int _serviceReconnectAttempt = 0;
  bool _loadingNotifications = false;
  bool _loadingAssignmentData = false;
  String? _reservingDriverId;
  final Map<String, DriverReservation> _reservations = {};
  final Set<String> _knownNotificationIds = {};
  List<InAppNotification> _notifications = const [];
  InAppNotification? _serviceRequestNotification;
  String? _notificationError;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get message => _message;
  String? get errorMessage => _errorMessage;
  List<TransportService> get services => _services;
  List<DriverRecord> get drivers => _drivers;
  List<VehicleRecord> get vehicles => _vehicles;
  List<InvitationRecord> get invitations => _invitations;
  List<LiveVehicleRecord> get liveVehicles => _liveVehicles;
  List<DriverLiveLocation> get liveDrivers => _liveDrivers;
  String? get liveVehiclesError => _liveVehiclesError;
  String? get liveDriversError => _liveDriversError;
  bool isRequestingDriver(String driverId) =>
      _requestingDriverIds.contains(driverId);
  String get adminName => _authRepository.currentUser?.fullName ?? 'Admin';
  bool get loadingAssignmentData => _loadingAssignmentData;
  String? get reservingDriverId => _reservingDriverId;
  InAppNotification? get serviceRequestNotification =>
      _serviceRequestNotification;
  String? get notificationError => _notificationError;
  List<InAppNotification> get notifications => _notifications;

  DriverReservation? reservationForService(String serviceId) =>
      _reservations[serviceId];

  void clearFeedback() {
    _message = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final isViewer = _authRepository.currentUser?.role == 'VIEWER';
      // Invitations are coordinator-only; their 403 must not block viewer Home.
      final results = await Future.wait<Object>([
        _adminRepository.services(),
        _adminRepository.drivers(),
        _adminRepository.vehicles(),
        if (!isViewer) _adminRepository.invitations(),
      ]);
      _services = results[0] as List<TransportService>;
      _drivers = _acceptDriverSnapshot(results[1] as List<DriverRecord>);
      _vehicles = results[2] as List<VehicleRecord>;
      _invitations = isViewer ? const [] : results[3] as List<InvitationRecord>;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadNotifications() async {
    if (_loadingNotifications || _disposed) return;
    _loadingNotifications = true;
    try {
      final notifications = await _notificationRepository.notifications();
      final newRequests = notifications
          .where(
            (item) =>
                !item.read &&
                item.isServiceRequest &&
                !_knownNotificationIds.contains(item.id),
          )
          .toList();
      _notifications = List.unmodifiable(notifications);
      _knownNotificationIds.addAll(
        notifications.map((notification) => notification.id),
      );
      if (_serviceRequestNotification == null && newRequests.isNotEmpty) {
        _serviceRequestNotification = newRequests.first;
      }
      _notificationError = null;
    } catch (error) {
      _notificationError = error.toString();
    } finally {
      _loadingNotifications = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<TransportService?> openServiceRequestNotification(
    InAppNotification notification,
  ) async {
    _serviceRequestNotification = null;
    notifyListeners();
    if (!notification.read) {
      try {
        await _notificationRepository.markRead(notification.id);
        _notifications = [
          for (final item in _notifications)
            if (item.id == notification.id) item.copyWith(read: true) else item,
        ];
      } catch (error) {
        _notificationError = error.toString();
      }
    }

    final serviceId = notification.targetServiceId;
    if (serviceId == null) return null;
    try {
      final service = await _adminRepository.serviceRequest(serviceId);
      _upsertService(service);
      _notificationError = null;
      notifyListeners();
      return service;
    } catch (error) {
      await refreshServices();
      for (final service in _services) {
        if (service.id == serviceId) return service;
      }
      _notificationError = error.toString();
      notifyListeners();
      return null;
    }
  }

  void dismissServiceRequestNotification() {
    _serviceRequestNotification = null;
    notifyListeners();
  }

  Future<void> refreshAssignmentData(String serviceId) async {
    if (_loadingAssignmentData) return;
    _loadingAssignmentData = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _drivers = _acceptDriverSnapshot(await _adminRepository.drivers());
      try {
        _upsertService(await _adminRepository.serviceRequest(serviceId));
      } catch (_) {
        if (!_services.any((service) => service.id == serviceId)) rethrow;
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _loadingAssignmentData = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> reserveDriverForService({
    required String serviceId,
    required String driverId,
  }) async {
    if (_reservingDriverId != null || _reservations.containsKey(serviceId)) {
      return false;
    }
    _reservingDriverId = driverId;
    _errorMessage = null;
    notifyListeners();
    try {
      final reservation = await _adminRepository.reserveDriver(
        serviceId: serviceId,
        driverId: driverId,
      );
      if (!reservation.confirmed) {
        _errorMessage =
            'El servidor no confirmó la reserva. Actualiza e intenta nuevamente.';
        await _refreshDriversAfterReservation();
        return false;
      }
      _reservations[serviceId] = reservation;
      _drivers = [
        for (final driver in _drivers)
          if (driver.id == driverId)
            driver.copyWith(
              availabilityStatus: 'RESERVADO',
              reservationOwner: reservation.owner,
              reservationId: reservation.id,
              vehicleId: reservation.vehicleId ?? reservation.driver?.vehicleId,
              vehicleModel:
                  reservation.vehicleModel ?? reservation.driver?.vehicleModel,
              vehiclePlate:
                  reservation.vehiclePlate ?? reservation.driver?.vehiclePlate,
            )
          else
            driver,
      ];
      return true;
    } on AppFailure catch (error) {
      if (error.kind == AppFailureKind.conflict) {
        _errorMessage =
            'Este conductor acaba de ser reservado por otro administrador. Selecciona otro.';
        await _refreshDriversAfterReservation();
      } else {
        _errorMessage = error.toString();
      }
      return false;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _reservingDriverId = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _refreshDriversAfterReservation() async {
    try {
      _drivers = _acceptDriverSnapshot(await _adminRepository.drivers());
    } catch (_) {
      // Keep the last backend snapshot; polling will try again shortly.
    }
  }

  List<DriverRecord> _acceptDriverSnapshot(List<DriverRecord> drivers) {
    _reservations.removeWhere((_, reservation) {
      DriverRecord? backendDriver;
      for (final driver in drivers) {
        if (driver.id == reservation.driverId) {
          backendDriver = driver;
          break;
        }
      }
      if (backendDriver == null ||
          backendDriver.normalizedAvailabilityStatus != 'RESERVADO') {
        return true;
      }
      final backendReservationId = backendDriver.reservationId;
      return backendReservationId != null &&
          backendReservationId != reservation.id;
    });
    return List.unmodifiable(drivers);
  }

  Future<void> loadLiveVehicles() async {
    if (_disposed || _loadingLiveVehicles) return;
    _loadingLiveVehicles = true;
    try {
      _liveVehicles = await _adminRepository.liveVehicles();
      _liveVehiclesError = null;
    } catch (error) {
      _liveVehiclesError = error.toString();
    } finally {
      _loadingLiveVehicles = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadLiveDrivers() async {
    if (_disposed || _loadingLiveDrivers) return;
    _loadingLiveDrivers = true;
    try {
      _liveDrivers = await _adminRepository.liveDrivers();
      _liveDriversError = null;
    } catch (error) {
      _liveDriversError = error.toString();
    } finally {
      _loadingLiveDrivers = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setLiveUpdatesEnabled(bool enabled) {
    if (_disposed || _liveUpdatesEnabled == enabled) return;
    _liveUpdatesEnabled = enabled;
    if (!enabled) {
      _liveFallbackTimer?.cancel();
      _liveFallbackTimer = null;
      _liveReconnectTimer?.cancel();
      _liveReconnectTimer = null;
      _serviceReconnectTimer?.cancel();
      _serviceReconnectTimer = null;
      _notificationTimer?.cancel();
      _notificationTimer = null;
      final subscription = _liveSubscription;
      _liveSubscription = null;
      unawaited(subscription?.cancel());
      final serviceSubscription = _serviceSubscription;
      _serviceSubscription = null;
      unawaited(serviceSubscription?.cancel());
      return;
    }

    unawaited(_refreshLiveSnapshots());
    unawaited(loadNotifications());
    _connectLiveStream();
    _connectServiceStream();
    _liveFallbackTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshLiveSnapshots()),
    );
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(loadNotifications()),
    );
  }

  Future<bool> requestDriverLocation(String driverId) async {
    if (!_requestingDriverIds.add(driverId)) return false;
    _message = null;
    _errorMessage = null;
    notifyListeners();
    try {
      final requestId = await _adminRepository.requestDriverLocations(
        driverIds: [driverId],
      );
      _message = 'Solicitud de ubicación enviada.';
      if (requestId != null) {
        unawaited(_refreshLocationRequest(requestId, driverId: driverId));
      }
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _requestingDriverIds.remove(driverId);
      notifyListeners();
    }
  }

  Future<void> _refreshLiveSnapshots() async {
    if (_disposed) return;
    await Future.wait([
      loadLiveVehicles(),
      loadLiveDrivers(),
      refreshServices(),
    ]);
  }

  Future<void> refreshServices() async {
    if (_disposed) return;
    try {
      final services = await _adminRepository.services();
      _services = services;
      if (_errorMessage != null && services.isNotEmpty) {
        _errorMessage = null;
      }
    } catch (error) {
      if (_services.isEmpty) _errorMessage = error.toString();
    }
    if (!_disposed) notifyListeners();
  }

  void _upsertService(TransportService service) {
    _services = [
      for (final item in _services)
        if (item.id != service.id) item,
      service,
    ];
  }

  void _connectServiceStream() {
    if (!_liveUpdatesEnabled || _serviceSubscription != null || _disposed) {
      return;
    }
    _serviceReconnectTimer?.cancel();
    _serviceReconnectTimer = null;
    _serviceSubscription = _adminRepository.serviceRequestEvents().listen(
      (_) {
        _serviceReconnectAttempt = 0;
        unawaited(refreshServices());
      },
      onError: (Object _, StackTrace _) => _serviceStreamDisconnected(),
      onDone: _serviceStreamDisconnected,
      cancelOnError: true,
    );
  }

  void _serviceStreamDisconnected() {
    _serviceSubscription = null;
    if (!_liveUpdatesEnabled || _serviceReconnectTimer != null || _disposed) {
      return;
    }
    const delays = [2, 4, 8, 16, 30];
    final index = _serviceReconnectAttempt.clamp(0, delays.length - 1).toInt();
    _serviceReconnectAttempt++;
    _serviceReconnectTimer = Timer(Duration(seconds: delays[index]), () {
      _serviceReconnectTimer = null;
      _connectServiceStream();
    });
  }

  void _connectLiveStream() {
    if (!_liveUpdatesEnabled || _liveSubscription != null || _disposed) return;
    _liveReconnectTimer?.cancel();
    _liveReconnectTimer = null;
    _liveSubscription = _adminRepository.liveDriverEvents().listen(
      _applyLiveDriverEvent,
      onError: (Object error, StackTrace stackTrace) {
        _liveDriversError =
            'Conexión en vivo interrumpida; se actualizará cada 30 s.';
        _liveStreamDisconnected();
      },
      onDone: _liveStreamDisconnected,
      cancelOnError: true,
    );
  }

  void _applyLiveDriverEvent(Map<String, dynamic> event) {
    final eventDriverId = _driverIdFromEvent(event);
    DriverLiveLocation? previous;
    if (eventDriverId != null) {
      for (final item in _liveDrivers) {
        if (item.driverId == eventDriverId) {
          previous = item;
          break;
        }
      }
    }
    final updated = DriverLiveLocation.tryParse(event, previous: previous);
    if (updated == null) return;
    _liveDrivers = [
      for (final item in _liveDrivers)
        if (item.driverId != updated.driverId) item,
      updated,
    ];
    _liveReconnectAttempt = 0;
    _liveDriversError = null;
    notifyListeners();
  }

  String? _driverIdFromEvent(Map<String, dynamic> event) {
    final data = event['data'];
    return data is Map<String, dynamic> ? data['driverId'] as String? : null;
  }

  void _liveStreamDisconnected() {
    _liveSubscription = null;
    if (!_liveUpdatesEnabled || _liveReconnectTimer != null) return;
    const delays = [2, 4, 8, 16, 30];
    final index = _liveReconnectAttempt.clamp(0, delays.length - 1).toInt();
    _liveReconnectAttempt++;
    _liveReconnectTimer = Timer(Duration(seconds: delays[index]), () {
      _liveReconnectTimer = null;
      _connectLiveStream();
    });
    notifyListeners();
  }

  Future<void> _refreshLocationRequest(
    String requestId, {
    String? driverId,
  }) async {
    // Se insiste varias veces: el teléfono puede tardar en responder y con una
    // sola consulta el mapa se quedaba con la posición vieja.
    final anterior = _liveDrivers
        .where((item) => item.driverId == driverId)
        .map((item) => item.capturedAt)
        .firstOrNull;
    for (var intento = 0; intento < 6; intento++) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!_liveUpdatesEnabled || _disposed) return;
      try {
        await _adminRepository.locationRequest(requestId);
        if (driverId == null) {
          await loadLiveDrivers();
          return;
        }
        final live = await _adminRepository.liveDriver(driverId);
        if (live == null) continue;
        _liveDrivers = [
          for (final item in _liveDrivers)
            if (item.driverId != live.driverId) item,
          live,
        ];
        notifyListeners();
        // Llegó una posición más nueva: no hace falta seguir preguntando.
        if (anterior == null || live.capturedAt != anterior) return;
      } catch (_) {
        // The SSE/fallback snapshot remains the source of truth for the map.
      }
    }
  }

  Future<bool> createRoute({
    required String pickupAddress,
    required String destinationAddress,
    required String driverId,
    required String vehicleId,
    required DateTime scheduledAt,
  }) async {
    await _run(() async {
      final route = await _adminRepository.createRoute(
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        driverId: driverId,
        vehicleId: vehicleId,
        scheduledAt: scheduledAt,
      );
      _message = 'Ruta ${route.code} creada y asignada.';
      await load();
    });
    return _errorMessage == null;
  }

  Future<bool> inviteDriver({
    required String email,
    required String driverName,
    required String documentNumber,
    required String phone,
    required String vehiclePlate,
    required String vehicleModel,
    required String vehicleType,
    required int seatCount,
  }) async {
    await _run(() async {
      final invitation = await _adminRepository.inviteDriver(
        email: email,
        driverName: driverName,
        documentNumber: documentNumber,
        phone: phone,
        vehiclePlate: vehiclePlate,
        vehicleModel: vehicleModel,
        vehicleType: vehicleType,
        seatCount: seatCount,
      );
      _message = 'Invitación enviada: ${invitation.invitationCode}';
      await load();
    });
    return _errorMessage == null;
  }

  Future<bool> cancelService(String serviceId) async {
    await _run(() async {
      final service = await _adminRepository.cancelService(serviceId);
      _message = 'Servicio ${service.code} cancelado.';
      await load();
    });
    return _errorMessage == null;
  }

  Future<bool> assignService({
    required String serviceId,
    required String driverId,
  }) async {
    final reservation = _reservations[serviceId];
    if (reservation == null ||
        !reservation.confirmed ||
        reservation.driverId != driverId) {
      _errorMessage = 'Primero reserva un conductor disponible.';
      notifyListeners();
      return false;
    }
    var vehicleId = reservation.vehicleId ?? reservation.driver?.vehicleId;
    if (vehicleId == null) {
      for (final driver in _drivers) {
        if (driver.id == driverId) {
          vehicleId = driver.vehicleId;
          break;
        }
      }
    }
    if (vehicleId == null || vehicleId.isEmpty) {
      _errorMessage =
          'La reserva confirmada no incluye un vehículo. Actualiza e intenta nuevamente.';
      notifyListeners();
      return false;
    }
    final confirmedVehicleId = vehicleId;
    await _run(() async {
      final service = await _adminRepository.assignService(
        serviceId: serviceId,
        driverId: driverId,
        vehicleId: confirmedVehicleId,
        reservationId: reservation.id,
      );
      _message = 'Servicio ${service.code} asignado.';
      _reservations.remove(serviceId);
      await load();
    });
    return _errorMessage == null;
  }

  Future<bool> toggleDriverStatus(DriverRecord driver) async {
    final targetStatus = driver.status.toUpperCase() == 'ACTIVE'
        ? 'INACTIVE'
        : 'ACTIVE';
    await _run(() async {
      final updated = await _adminRepository.updateDriverStatus(
        driver.id,
        targetStatus,
      );
      final action = targetStatus == 'ACTIVE' ? 'activado' : 'desactivado';
      _message = 'Driver ${updated.fullName} $action.';
      await load();
    });
    return _errorMessage == null;
  }

  Future<String?> downloadServicesReport() async {
    String? path;
    await _run(() async {
      path = await _adminRepository.downloadServicesReport();
      _message = 'Reporte PDF generado.';
    });
    return path;
  }

  Future<void> logout() {
    setLiveUpdatesEnabled(false);
    return _authRepository.logout();
  }

  Future<void> _run(Future<void> Function() action) async {
    _isLoading = true;
    _message = null;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _liveUpdatesEnabled = false;
    _liveFallbackTimer?.cancel();
    _liveReconnectTimer?.cancel();
    _serviceReconnectTimer?.cancel();
    _notificationTimer?.cancel();
    unawaited(_liveSubscription?.cancel());
    unawaited(_serviceSubscription?.cancel());
    super.dispose();
  }
}
