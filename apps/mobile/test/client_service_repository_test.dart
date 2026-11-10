import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_driver/data/repositories/client_service_repository.dart';
import 'package:mobile_driver/data/services/api_client.dart';
import 'package:mobile_driver/data/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('myServices junta las solicitudes en curso con los servicios', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      final body = switch (request.url.path) {
        '/api/client/services' => {
          'services': [_serviceJson(id: 'a'), _serviceJson(id: 'b')],
        },
        '/api/client/requests' => {
          'requests': [
            // Todavía sin conductor: alimenta la pantalla de búsqueda.
            _requestJson(id: 'r1', status: 'BUSCANDO_CONDUCTOR'),
          ],
        },
        _ => fail('ruta inesperada: ${request.url.path}'),
      };
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = await _repository(client);

    final services = await repository.myServices();

    expect(services, hasLength(3));
    // La solicitud en curso va primero: es lo que el cliente está esperando.
    expect(services.first.id, 'r1');
    expect(services.first.currentStatus, 'BUSCANDO_CONDUCTOR');
    expect(services.first.isSearchingForDriver, isTrue);
    expect(services[1].id, 'a');
    expect(services[1].code, 'SRV-a');
    expect(services[1].currentStatus, 'PROGRAMADO');
    expect(services[1].notes, 'Ventana 9-10');
  });

  test(
    'myServices no duplica una solicitud que ya derivó en servicio',
    () async {
      final client = MockClient((request) async {
        final body = switch (request.url.path) {
          '/api/client/services' => {
            'services': [_serviceJson(id: 'a')],
          },
          '/api/client/requests' => {
            'requests': [
              _requestJson(id: 'r1', status: 'ATENDIDA', serviceId: 'a'),
            ],
          },
          _ => fail('ruta inesperada: ${request.url.path}'),
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repository = await _repository(client);

      final services = await repository.myServices();

      expect(services, hasLength(1));
      expect(services.single.id, 'a');
    },
  );

  test(
    'requestService pide por el flujo de solicitudes, que avisa al admin',
    () async {
      Map<String, dynamic>? sentBody;
      final scheduledAt = DateTime.now().add(const Duration(hours: 1));

      final client = MockClient((request) async {
        expect(request.method, 'POST');
        // Clave: /client/requests y NO /client/services. Sólo esta ruta dispara
        // el aviso a los administradores y la búsqueda de conductor.
        expect(request.url.path, '/api/client/requests');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'request': _serviceJson(id: 'a')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repository = await _repository(client);

      final service = await repository.requestService(
        scheduledAt: scheduledAt,
        pickupAddress: 'Ubicación actual',
        pickupLatitude: -12.0464,
        pickupLongitude: -77.0428,
        destinationAddress: 'Av. Lima 1234, Miraflores',
        destinationLatitude: -12.12,
        destinationLongitude: -77.03,
        notes: 'Ventana 9-10',
      );

      expect(sentBody, isNotNull);
      expect(sentBody!.keys.toSet(), {
        'scheduledAt',
        'pickupAddress',
        'pickupLatitude',
        'pickupLongitude',
        'destinationAddress',
        'destinationLatitude',
        'destinationLongitude',
        'notes',
      });
      expect(sentBody!['pickupAddress'], 'Ubicación actual');
      expect(sentBody!['pickupLatitude'], -12.0464);
      expect(sentBody!['pickupLongitude'], -77.0428);
      expect(sentBody!['destinationLatitude'], -12.12);
      expect(sentBody!['destinationLongitude'], -77.03);
      expect(sentBody!['notes'], 'Ventana 9-10');
      expect(
        DateTime.parse(
          sentBody!['scheduledAt'] as String,
        ).isAfter(DateTime.now().toUtc()),
        isTrue,
      );
      expect(service.id, 'a');
      expect(service.currentStatus, 'PROGRAMADO');
    },
  );

  test('requestService omits blank notes from the body', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'service': _serviceJson(id: 'a')}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = await _repository(client);

    await repository.requestService(
      scheduledAt: DateTime.now().add(const Duration(minutes: 30)),
      pickupAddress: 'Ubicación actual',
      pickupLatitude: -12.0464,
      pickupLongitude: -77.0428,
      destinationAddress: 'Av. Lima 1234, Miraflores',
      destinationLatitude: -12.12,
      destinationLongitude: -77.03,
      notes: '   ',
    );

    expect(sentBody, isNotNull);
    expect(sentBody!.containsKey('notes'), isFalse);
  });

  test('requestService surfaces the server validation error', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'scheduledAt debe estar en el futuro'}),
        400,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = await _repository(client);

    expect(
      () => repository.requestService(
        scheduledAt: DateTime.now().add(const Duration(minutes: 30)),
        pickupAddress: 'Ubicación actual',
        pickupLatitude: -12.0464,
        pickupLongitude: -77.0428,
        destinationAddress: 'Av. Lima 1234, Miraflores',
        destinationLatitude: -12.12,
        destinationLongitude: -77.03,
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains('scheduledAt debe estar'),
        ),
      ),
    );
  });
}

Future<ClientServiceRepository> _repository(http.Client client) async {
  final store = await SessionStore.create();
  final apiClient = ApiClient(
    sessionStore: store,
    baseUri: Uri.parse('https://example.test/api'),
    client: client,
  );
  return ClientServiceRepository(apiClient: apiClient);
}

/// Solicitud tal como la devuelve `/client/requests`: usa `status` en vez de
/// `currentStatus` y puede traer `serviceId` una vez confirmada.
Map<String, dynamic> _requestJson({
  required String id,
  required String status,
  String? serviceId,
}) {
  return {
    'id': id,
    'code': 'REQ-$id',
    'status': status,
    'serviceId': serviceId,
    'scheduledAt': DateTime.now()
        .add(const Duration(hours: 1))
        .toUtc()
        .toIso8601String(),
    'pickupAddress': 'Ubicación actual',
    'pickupLatitude': -12.0464,
    'pickupLongitude': -77.0428,
    'destinationAddress': 'Av. Lima 1234, Miraflores, Lima, Perú',
    'destinationLatitude': -12.12,
    'destinationLongitude': -77.03,
  };
}

Map<String, dynamic> _serviceJson({required String id}) {
  return {
    'id': id,
    'code': 'SRV-$id',
    'scheduledAt': DateTime.now()
        .add(const Duration(hours: 1))
        .toUtc()
        .toIso8601String(),
    'pickupAddress': 'Ubicación actual',
    'pickupLatitude': -12.0464,
    'pickupLongitude': -77.0428,
    'destinationAddress': 'Av. Lima 1234, Miraflores, Lima, Perú',
    'destinationLatitude': -12.12,
    'destinationLongitude': -77.03,
    'currentStatus': 'PROGRAMADO',
    'notes': 'Ventana 9-10',
  };
}
