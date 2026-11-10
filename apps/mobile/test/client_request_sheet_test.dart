import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_driver/data/repositories/client_service_repository.dart';
import 'package:mobile_driver/data/services/api_client.dart';
import 'package:mobile_driver/data/services/location_service.dart';
import 'package:mobile_driver/data/services/road_routing_service.dart';
import 'package:mobile_driver/data/services/session_store.dart';
import 'package:mobile_driver/domain/models/location_point.dart';
import 'package:mobile_driver/ui/features/client/view_models/client_view_model.dart';
import 'package:mobile_driver/ui/features/client/views/client_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the resolved GPS address and submits a request', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({'services': <Object>[]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      return http.Response(
        jsonEncode({'service': _serviceJson(body)}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final viewModel = await _viewModel(httpClient: client);

    await _pumpSheet(tester, viewModel);

    expect(find.text('Av. GPS 123, Lima'), findsOneWidget);
    expect(find.textContaining('-12.0464'), findsNothing);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Av. Lima 1234, Miraflores',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Solicitar servicio'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.first['pickupAddress'], 'Av. GPS 123, Lima');
    expect(requests.first['pickupLatitude'], -12.0464);
    expect(requests.first['destinationLatitude'], -12.1);
    expect(requests.first['destinationAddress'], 'Av. Lima 1234, Miraflores');
    expect(find.text('Solicitud enviada'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('allows replacing the GPS origin with another address', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final client = MockClient((request) async {
      submitted = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'service': _serviceJson(submitted!)}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final viewModel = await _viewModel(httpClient: client);

    await _pumpSheet(tester, viewModel);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Aeropuerto Jorge Chávez, Callao',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Av. Lima 1234, Miraflores',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Solicitar servicio'));
    await tester.pumpAndSettle();

    expect(submitted?['pickupAddress'], 'Aeropuerto Jorge Chávez, Callao');
    expect(submitted?['pickupLatitude'], -12.1);
    expect(find.text('Solicitud enviada'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  });

  testWidgets('blocks a second submit while the first is in flight', (
    tester,
  ) async {
    final completer = Completer<http.Response>();
    var postCalls = 0;
    final client = MockClient((request) {
      if (request.method == 'POST') postCalls++;
      return completer.future;
    });
    final viewModel = await _viewModel(httpClient: client);

    await _pumpSheet(tester, viewModel);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Av. Lima 1234, Miraflores',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Solicitar servicio'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Enviando solicitud…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Enviando solicitud…'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Enviando solicitud…'), warnIfMissed: false);
    await tester.pump();
    expect(postCalls, 1);

    completer.complete(
      http.Response(
        jsonEncode({'service': _serviceJson(const {})}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Solicitud enviada'), findsOneWidget);
    expect(postCalls, 1);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a network failure shows an error and never claims the request was queued',
    (tester) async {
      final client = MockClient((request) async {
        throw http.ClientException('Connection refused');
      });
      final viewModel = await _viewModel(httpClient: client);

      await _pumpSheet(tester, viewModel);

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Av. Lima 1234, Miraflores',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Solicitar servicio'));
      await tester.pumpAndSettle();

      expect(find.text('Solicitud enviada'), findsNothing);
      expect(find.text('Programado'), findsNothing);
      expect(
        find.textContaining('No se pudo enviar la solicitud'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an ungeocodable destination shows a location error without '
      'submitting', (tester) async {
    var postCalls = 0;
    final client = MockClient((request) async {
      postCalls++;
      return http.Response(
        jsonEncode({'service': _serviceJson(const {})}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final viewModel = await _viewModel(
      httpClient: client,
      routing: _FakeRouting(point: const LatLng(-12.1, -77.03), fail: true),
    );

    await _pumpSheet(tester, viewModel);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Dirección que no existe en ningún mapa',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Solicitar servicio'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No encontramos esa dirección'), findsOneWidget);
    expect(postCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<ClientViewModel> _viewModel({
  required http.Client httpClient,
  LocationService? location,
  RoadRoutingService? routing,
}) async {
  final store = await SessionStore.create();
  final apiClient = ApiClient(
    sessionStore: store,
    baseUri: Uri.parse('https://example.test/api'),
    client: httpClient,
  );
  return ClientViewModel(
    clientServiceRepository: ClientServiceRepository(apiClient: apiClient),
    locationService: location ?? _FakeLocationService(),
    sessionStore: store,
    roadRoutingService:
        routing ?? const _FakeRouting(point: LatLng(-12.1, -77.03)),
  );
}

Future<void> _pumpSheet(WidgetTester tester, ClientViewModel viewModel) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => ClientRequestSheet(
                  viewModel: viewModel,
                  onPickupPointChanged: (_) {},
                  onDestinationPointChanged: (_) {},
                ),
              ),
              child: const Text('Abrir solicitud'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir solicitud'));
  await tester.pumpAndSettle();
}

class _FakeLocationService extends LocationService {
  @override
  Future<LocationPoint> currentLocation() async {
    return const LocationPoint(
      latitude: -12.0464,
      longitude: -77.0428,
      accuracy: 12,
    );
  }
}

class _FakeRouting extends RoadRoutingService {
  const _FakeRouting({required this.point, this.fail = false});

  final LatLng point;
  final bool fail;

  @override
  Future<LatLng> geocode(String address) async {
    if (fail) {
      throw const RoadRoutingException('No encontramos la dirección.');
    }
    return point;
  }

  @override
  Future<String> reverseGeocode(LatLng point) async => 'Av. GPS 123, Lima';
}

Map<String, dynamic> _serviceJson(Map<String, dynamic> body) {
  return {
    'id': 'service-1',
    'code': 'SRV-001',
    'scheduledAt': DateTime.now().toUtc().toIso8601String(),
    'pickupAddress': body['pickupAddress'] ?? 'Ubicación actual',
    'pickupLatitude': body['pickupLatitude'] ?? -12.0464,
    'pickupLongitude': body['pickupLongitude'] ?? -77.0428,
    'destinationAddress':
        body['destinationAddress'] ?? 'Av. Lima 1234, Miraflores',
    'destinationLatitude': body['destinationLatitude'] ?? -12.1,
    'destinationLongitude': body['destinationLongitude'] ?? -77.03,
    'currentStatus': 'PROGRAMADO',
  };
}
