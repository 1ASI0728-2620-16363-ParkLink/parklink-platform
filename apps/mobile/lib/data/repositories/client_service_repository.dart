import '../../domain/models/transport_service.dart';
import '../services/api_client.dart';

abstract final class ClientServiceApiEndpoints {
  static const services = '/client/services';
  static const serviceEvents = '/client/services/stream';

  /// Flujo de solicitudes: es el que avisa a los administradores (push,
  /// realtime y notificación in-app) y el que dispara la búsqueda de
  /// conductor. `/client/services` crea el viaje directo, sin avisar a nadie.
  static const requests = '/client/requests';
}

class ClientServiceRepository {
  ClientServiceRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Servicios del cliente: las solicitudes en curso y los viajes ya
  /// confirmados.
  ///
  /// Se consultan las dos listas porque viven en tablas distintas: mientras un
  /// pedido se está atendiendo es una solicitud (y su estado alimenta la
  /// pantalla de "buscando conductor"); recién al confirmarse nace el
  /// servicio. Si una solicitud ya derivó en servicio se descarta, para no
  /// mostrar el mismo viaje dos veces.
  Future<List<TransportService>> myServices() async {
    final responses = await Future.wait([
      _apiClient.getJson(ClientServiceApiEndpoints.services),
      _apiClient.getJson(ClientServiceApiEndpoints.requests),
    ]);

    final services = _parseList(responses[0], 'services');
    final requests = _parseList(
      responses[1],
      'requests',
    ).where((request) => request['serviceId'] == null);

    return [
      ...requests,
      ...services,
    ].map(TransportService.fromJson).toList(growable: false);
  }

  List<Map<String, dynamic>> _parseList(
    Map<String, dynamic> response,
    String key,
  ) {
    final data = response['data'];
    final raw =
        response[key] ?? (data is Map<String, dynamic> ? data[key] : data);
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Stream<Map<String, dynamic>> serviceEvents() {
    return _apiClient.streamSseJson(ClientServiceApiEndpoints.serviceEvents);
  }

  Future<TransportService> requestService({
    required DateTime scheduledAt,
    required String pickupAddress,
    required double pickupLatitude,
    required double pickupLongitude,
    required String destinationAddress,
    required double destinationLatitude,
    required double destinationLongitude,
    String? notes,
  }) async {
    final response = await _apiClient
        .postJson(ClientServiceApiEndpoints.requests, {
          'scheduledAt': scheduledAt.toUtc().toIso8601String(),
          'pickupAddress': pickupAddress,
          'pickupLatitude': pickupLatitude,
          'pickupLongitude': pickupLongitude,
          'destinationAddress': destinationAddress,
          'destinationLatitude': destinationLatitude,
          'destinationLongitude': destinationLongitude,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        });
    final service = TransportService.tryFromEnvelope(response);
    if (service == null) {
      throw const FormatException('Service request response without service.');
    }
    return service;
  }
}
