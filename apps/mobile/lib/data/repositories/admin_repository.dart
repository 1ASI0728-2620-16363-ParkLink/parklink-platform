import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/admin_records.dart';
import '../../domain/models/transport_service.dart';
import '../services/api_client.dart';
import '../services/road_routing_service.dart';

abstract final class AdminApiEndpoints {
  static const services = '/services';
  static const serviceEvents = '/services/stream';
  static const drivers = '/drivers';
  static const vehicles = '/vehicles';
  static const liveVehicles = '/vehicles/live';
  static const liveDrivers = '/drivers/live';
  static const liveDriverEvents = '/drivers/live/stream';
  static const driverLocationRequests = '/drivers/location-requests';
  static const invitations = '/invitations';
  static const servicesReport = '/reports/services.pdf';
  static const assignments = '/assignments';
  static const assignmentReservations = '/assignments/reservations';

  static String service(String serviceId) => '/services/$serviceId';
  static String driver(String driverId) => '/drivers/$driverId';
  static String liveDriver(String driverId) => '/drivers/$driverId/live';
  static String driverLocationRequest(String requestId) =>
      '/drivers/location-requests/$requestId';
}

class AdminRepository {
  AdminRepository({
    required ApiClient apiClient,
    RoadRoutingService roadRoutingService = const RoadRoutingService(),
  }) : _apiClient = apiClient,
       _roadRoutingService = roadRoutingService;

  final ApiClient _apiClient;
  final RoadRoutingService _roadRoutingService;

  /// Tope de paginas que se traen de una. A 100 por pagina son 500 servicios,
  /// de sobra para la agenda que un coordinador mira, y evita que un historial
  /// crecido dispare decenas de consultas en cada refresco.
  static const _maxPaginasDeServicios = 5;

  /// Todos los servicios, siguiendo el cursor.
  ///
  /// El endpoint quedo paginado y devuelve diez por defecto: pedido sin
  /// parametros, el panel del admin solo veia los diez mas recientes y parecia
  /// que mostraba unicamente los pendientes. `includeActive` trae ademas los
  /// que estan en curso, que no pueden faltar aunque haya historial delante.
  Future<List<TransportService>> services() async {
    final acumulado = <TransportService>[];
    String? cursor;
    for (var pagina = 0; pagina < _maxPaginasDeServicios; pagina += 1) {
      final parametros = <String, String>{
        'limit': '100',
        if (cursor == null) 'includeActive': 'true' else 'cursor': cursor,
      };
      final consulta = parametros.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final response = await _apiClient.getJson(
        '${AdminApiEndpoints.services}?$consulta',
      );
      final data = response['data'];
      final raiz = data is Map<String, dynamic> ? data : response;
      final records = raiz['services'] ?? (data is List ? data : null);
      if (records is! List) break;
      acumulado.addAll(
        records.whereType<Map<String, dynamic>>().map(TransportService.fromJson),
      );
      final siguiente = raiz['nextCursor'];
      if (siguiente is! String || siguiente.isEmpty) break;
      cursor = siguiente;
    }
    // El primer tramo repite los activos que ya vienen en el historial.
    final vistos = <String>{};
    return [
      for (final servicio in acumulado)
        if (vistos.add(servicio.id)) servicio,
    ];
  }

  Future<TransportService> serviceRequest(String serviceId) async {
    final response = await _apiClient.getJson(
      AdminApiEndpoints.service(serviceId),
    );
    final service = TransportService.tryFromEnvelope(response);
    if (service == null) {
      throw const FormatException('Service response without service.');
    }
    return service;
  }

  Stream<Map<String, dynamic>> serviceRequestEvents() {
    return _apiClient.streamSseJson(AdminApiEndpoints.serviceEvents);
  }

  Future<List<DriverRecord>> drivers() async {
    final response = await _apiClient.getJson(AdminApiEndpoints.drivers);
    final data = response['data'];
    final records =
        response['drivers'] ??
        (data is Map<String, dynamic> ? data['drivers'] : data);
    if (records is! List) return const [];
    return records
        .whereType<Map<String, dynamic>>()
        .map(DriverRecord.fromJson)
        .toList();
  }

  Future<List<VehicleRecord>> vehicles() async {
    final response = await _apiClient.getJson(AdminApiEndpoints.vehicles);
    return (response['vehicles'] as List<dynamic>)
        .map((json) => VehicleRecord.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<LiveVehicleRecord>> liveVehicles() async {
    final response = await _apiClient.getJson(AdminApiEndpoints.liveVehicles);
    final records = response['vehicles'];
    if (records is! List) return const [];
    return records
        .whereType<Map<String, dynamic>>()
        .map(LiveVehicleRecord.fromJson)
        .toList();
  }

  Future<List<DriverLiveLocation>> liveDrivers() async {
    final response = await _apiClient.getJson(AdminApiEndpoints.liveDrivers);
    final records = response['drivers'];
    if (records is! List) return const [];
    return records
        .whereType<Map<String, dynamic>>()
        .map((json) => DriverLiveLocation.tryParse(json))
        .whereType<DriverLiveLocation>()
        .toList();
  }

  Stream<Map<String, dynamic>> liveDriverEvents() {
    return _apiClient.streamSseJson(AdminApiEndpoints.liveDriverEvents);
  }

  Future<DriverLiveLocation?> liveDriver(String driverId) async {
    final response = await _apiClient.getJson(
      AdminApiEndpoints.liveDriver(driverId),
    );
    final raw = response['driver'];
    return raw is Map<String, dynamic>
        ? DriverLiveLocation.tryParse(raw)
        : null;
  }

  Future<String?> requestDriverLocations({List<String>? driverIds}) async {
    final response = await _apiClient.postJson(
      AdminApiEndpoints.driverLocationRequests,
      {'driverIds': ?driverIds},
    );
    final request = response['request'] as Map<String, dynamic>;
    return request['id'] as String?;
  }

  Future<Map<String, dynamic>> locationRequest(String requestId) {
    return _apiClient.getJson(
      AdminApiEndpoints.driverLocationRequest(requestId),
    );
  }

  Future<List<InvitationRecord>> invitations() async {
    final response = await _apiClient.getJson(AdminApiEndpoints.invitations);
    return (response['invitations'] as List<dynamic>)
        .map((json) => InvitationRecord.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<String> downloadServicesReport() async {
    final bytes = await _apiClient.getBytes(AdminApiEndpoints.servicesReport);
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(
      p.join(directory.path, 'reporte-consolidado-rutas-$timestamp.pdf'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<TransportService> cancelService(String serviceId) async {
    final response = await _apiClient.patchJson(
      AdminApiEndpoints.service(serviceId),
      {'currentStatus': 'CANCELADO'},
    );
    return TransportService.fromJson(
      response['service'] as Map<String, dynamic>,
    );
  }

  Future<DriverRecord> updateDriverStatus(
    String driverId,
    String status,
  ) async {
    final response = await _apiClient.patchJson(
      AdminApiEndpoints.driver(driverId),
      {'status': status},
    );
    return DriverRecord.fromJson(response['driver'] as Map<String, dynamic>);
  }

  Future<TransportService> createRoute({
    required String pickupAddress,
    required String destinationAddress,
    required String driverId,
    required String vehicleId,
    required DateTime scheduledAt,
  }) async {
    final pickup = await _roadRoutingService.geocode(pickupAddress);
    await Future<void>.delayed(const Duration(seconds: 1));
    final destination = await _roadRoutingService.geocode(destinationAddress);

    // El conductor y el vehículo van en el alta: el backend crea el servicio y
    // su asignación en una sola transacción. Antes se creaba primero y se
    // asignaba después, y si ese segundo paso fallaba quedaba un viaje sin
    // conductor.
    final created = await _apiClient.postJson(AdminApiEndpoints.services, {
      'driverId': driverId,
      'vehicleId': vehicleId,
      'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      'pickupAddress': pickupAddress,
      'pickupLatitude': pickup.latitude,
      'pickupLongitude': pickup.longitude,
      'destinationAddress': destinationAddress,
      'destinationLatitude': destination.latitude,
      'destinationLongitude': destination.longitude,
      'notes': 'Ruta creada desde panel móvil admin',
    });
    return TransportService.fromJson(
      created['service'] as Map<String, dynamic>,
    );
  }

  Future<TransportService> assignService({
    required String serviceId,
    required String driverId,
    required String vehicleId,
    required String reservationId,
  }) async {
    final response = await _apiClient.postJson(AdminApiEndpoints.assignments, {
      'serviceId': serviceId,
      'driverId': driverId,
      'vehicleId': vehicleId,
      'reservationId': reservationId,
    });
    return TransportService.fromJson(
      response['service'] as Map<String, dynamic>,
    );
  }

  Future<DriverReservation> reserveDriver({
    required String serviceId,
    required String driverId,
  }) async {
    final response = await _apiClient.postJson(
      AdminApiEndpoints.assignmentReservations,
      {'serviceId': serviceId, 'driverId': driverId},
    );
    return DriverReservation.fromJson(
      response,
      fallbackServiceId: serviceId,
      fallbackDriverId: driverId,
    );
  }

  Future<InvitationRecord> inviteDriver({
    required String email,
    required String driverName,
    required String documentNumber,
    required String phone,
    required String vehiclePlate,
    required String vehicleModel,
    required String vehicleType,
    required int seatCount,
  }) async {
    final response = await _apiClient.postJson(AdminApiEndpoints.invitations, {
      'email': email,
      'role': 'DRIVER',
      'driverName': driverName,
      'documentNumber': documentNumber,
      'phone': phone,
      'vehiclePlate': vehiclePlate,
      'vehicleModel': vehicleModel,
      'vehicleType': vehicleType,
      'seatCount': seatCount,
    });
    return InvitationRecord.fromJson(
      response['invitation'] as Map<String, dynamic>,
    );
  }
}
