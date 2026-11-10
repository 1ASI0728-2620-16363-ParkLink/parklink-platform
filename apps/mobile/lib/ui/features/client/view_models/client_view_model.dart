import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../data/repositories/client_service_repository.dart';
import '../../../../data/services/location_service.dart';
import '../../../../data/services/road_routing_service.dart';
import '../../../../data/services/session_store.dart';
import '../../../../domain/models/auth_session.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../domain/models/transport_service.dart';

class ClientViewModel extends ChangeNotifier {
  ClientViewModel({
    required ClientServiceRepository clientServiceRepository,
    required LocationService locationService,
    required SessionStore sessionStore,
    RoadRoutingService roadRoutingService = const RoadRoutingService(),
  }) : _clientServiceRepository = clientServiceRepository,
       _locationService = locationService,
       _sessionStore = sessionStore,
       _roadRoutingService = roadRoutingService;

  final ClientServiceRepository _clientServiceRepository;
  final LocationService _locationService;
  final SessionStore _sessionStore;
  final RoadRoutingService _roadRoutingService;

  List<TransportService> _services = const [];
  bool _loadingServices = false;
  bool _hasServerSnapshot = false;
  String? _servicesError;
  bool _submitting = false;
  String? _submissionError;
  TransportService? _lastSubmitted;
  StreamSubscription<Map<String, dynamic>>? _serviceSubscription;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _serverUpdatesEnabled = false;
  bool _searchingForReplacement = false;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  List<TransportService> get services => _services;
  bool get loadingServices => _loadingServices;
  String? get servicesError => _servicesError;
  bool get submitting => _submitting;
  String? get submissionError => _submissionError;
  TransportService? get lastSubmitted => _lastSubmitted;
  UserProfile? get user => _sessionStore.user;
  bool get searchingForReplacement => _searchingForReplacement;
  RoadRoutingService get roadRoutingService => _roadRoutingService;

  TransportService? get activeRequest {
    TransportService? active;
    for (final service in _services) {
      if (service.isTerminal) continue;
      if (active == null || service.scheduledAt.isAfter(active.scheduledAt)) {
        active = service;
      }
    }
    return active;
  }

  bool get hasActiveRequest => activeRequest != null;
  bool get canSubmitRequest => !_submitting && !hasActiveRequest;
  bool get canOpenRequestSheet =>
      _hasServerSnapshot &&
      !_loadingServices &&
      !_submitting &&
      !hasActiveRequest;

  Future<void> loadServices() async {
    if (_disposed || _loadingServices) return;
    _loadingServices = true;
    notifyListeners();
    try {
      final services = await _clientServiceRepository.myServices();
      if (_disposed) return;
      _replaceServices(services);
      _hasServerSnapshot = true;
      _servicesError = null;
    } catch (error) {
      if (_disposed) return;
      _servicesError = error.toString();
    } finally {
      _loadingServices = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setServerUpdatesEnabled(bool enabled) {
    if (_serverUpdatesEnabled == enabled || _disposed) return;
    _serverUpdatesEnabled = enabled;
    if (!enabled) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      final subscription = _serviceSubscription;
      _serviceSubscription = null;
      unawaited(subscription?.cancel());
      return;
    }

    unawaited(loadServices());
    _connectServiceStream();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(loadServices()),
    );
  }

  /// Motivo real del último fallo de ubicación o geocodificación.
  ///
  /// Estos métodos devuelven `null` en vez de propagar la excepción, así que
  /// sin esto la pantalla solo podía mostrar un mensaje genérico y el error
  /// verdadero (permiso denegado, GPS apagado, cuota de Google) se perdía.
  String? lastLocationFailure;

  Future<LocationPoint?> currentLocation() async {
    try {
      lastLocationFailure = null;
      return await _locationService.currentLocation();
    } on AppFailure catch (error) {
      lastLocationFailure = error.message;
      return null;
    } catch (_) {
      lastLocationFailure = null;
      return null;
    }
  }

  Future<LatLng?> geocode(String address) async {
    try {
      lastLocationFailure = null;
      return await _roadRoutingService.geocode(address);
    } on RoadRoutingException catch (error) {
      lastLocationFailure = error.message;
      return null;
    } catch (_) {
      lastLocationFailure = null;
      return null;
    }
  }

  Future<String?> reverseGeocode(LatLng point) async {
    try {
      lastLocationFailure = null;
      return await _roadRoutingService.reverseGeocode(point);
    } on RoadRoutingException catch (error) {
      lastLocationFailure = error.message;
      return null;
    } catch (_) {
      lastLocationFailure = null;
      return null;
    }
  }

  Future<TransportService?> submitRequest({
    required LatLng pickup,
    required String pickupAddress,
    required LatLng destination,
    required String destinationAddress,
    String? notes,
    DateTime? scheduledAt,
  }) async {
    if (_disposed) return null;
    if (!canSubmitRequest) {
      if (hasActiveRequest) {
        _submissionError =
            'Ya tienes una solicitud activa. Espera a que finalice antes de crear otra.';
        notifyListeners();
      }
      return null;
    }
    _submitting = true;
    _submissionError = null;
    _lastSubmitted = null;
    notifyListeners();
    try {
      final service = await _clientServiceRepository.requestService(
        scheduledAt:
            scheduledAt ?? DateTime.now().add(const Duration(minutes: 30)),
        pickupAddress: pickupAddress.trim(),
        pickupLatitude: pickup.latitude,
        pickupLongitude: pickup.longitude,
        destinationAddress: destinationAddress.trim(),
        destinationLatitude: destination.latitude,
        destinationLongitude: destination.longitude,
        notes: notes,
      );
      if (_disposed) return null;
      _lastSubmitted = service;
      _upsertService(service);
      unawaited(loadServices());
      return service;
    } catch (error) {
      if (_disposed) return null;
      _submissionError = error.toString();
      return null;
    } finally {
      _submitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void clearSubmissionFeedback() {
    _submissionError = null;
    _lastSubmitted = null;
    notifyListeners();
  }

  void _connectServiceStream() {
    if (!_serverUpdatesEnabled || _serviceSubscription != null || _disposed) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _serviceSubscription = _clientServiceRepository.serviceEvents().listen(
      (_) {
        _reconnectAttempt = 0;
        _servicesError = null;
        unawaited(loadServices());
      },
      onError: (Object _, StackTrace _) => _serviceStreamDisconnected(),
      onDone: _serviceStreamDisconnected,
      cancelOnError: true,
    );
  }

  void _serviceStreamDisconnected() {
    _serviceSubscription = null;
    if (!_serverUpdatesEnabled || _reconnectTimer != null || _disposed) return;
    const delays = [2, 4, 8, 16, 30];
    final index = _reconnectAttempt.clamp(0, delays.length - 1).toInt();
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delays[index]), () {
      _reconnectTimer = null;
      _connectServiceStream();
    });
  }

  void _replaceServices(List<TransportService> services) {
    final previousActive = activeRequest;
    _services = List.unmodifiable(services);
    _updateReplacementSearch(previousActive, activeRequest);
  }

  void _upsertService(TransportService service) {
    TransportService? previous;
    for (final item in _services) {
      if (item.id == service.id) {
        previous = item;
        break;
      }
    }
    _services = List.unmodifiable([
      for (final item in _services)
        if (item.id != service.id) item,
      service,
    ]);
    _updateReplacementSearch(previous, service);
    notifyListeners();
  }

  void _updateReplacementSearch(
    TransportService? previous,
    TransportService? current,
  ) {
    if (current == null || !current.isSearchingForDriver) {
      _searchingForReplacement = false;
      return;
    }
    if (previous?.id == current.id &&
        previous!.hasAssignedDriver &&
        !previous.isSearchingForDriver) {
      _searchingForReplacement = true;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _serverUpdatesEnabled = false;
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_serviceSubscription?.cancel());
    super.dispose();
  }
}
