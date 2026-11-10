import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_driver/data/repositories/parking_repository.dart';
import 'package:mobile_driver/ui/features/parking/views/parklink_app.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('login uses ParkLink endpoint and isolates secure storage from transport sessions', () async {
    final repo = ParkingRepository(client: MockClient((request) async {
      expect(request.url.path, '/auth/login');
      expect(jsonDecode(request.body), {'email': 'owner@example.com', 'password': 'long-password'});
      return http.Response(jsonEncode({'token': 'test-token', 'expiresIn': 3600, 'user': {'id': 'owner-id', 'name': 'Owner', 'roles': ['DRIVER', 'OWNER']}}), 201);
    }));
    await repo.login('owner@example.com', 'long-password');
    expect(repo.authenticated, isTrue); expect(repo.isOwner, isTrue);
    final restored = ParkingRepository(); await restored.restore(); expect(restored.isOwner, isTrue);
    await restored.logout(); expect(restored.authenticated, isFalse);
  });
  test('search maps real API results and never supplies fallback inventory', () async {
    final repo = ParkingRepository(client: MockClient((request) async {
      expect(request.url.path, '/discovery/search'); expect(request.url.queryParameters['radius'], '1000');
      return http.Response(jsonEncode({'items': [], 'informationalOnly': true}), 200);
    }));
    expect(await repo.search(-12, -77), isEmpty);
  });
  test('a failed operation is not presented as a successful booking', () async {
    final repo = ParkingRepository(client: MockClient((request) async {
      if (request.method == 'POST') return http.Response(jsonEncode({'commandId': 'command-1'}), 202);
      return http.Response(jsonEncode({'status': 'FAILED', 'http_status': 409, 'result': {'message': 'Interval unavailable'}}), 200);
    }));
    await expectLater(repo.command('hold', {'spaceId': 'space-1'}), throwsA(isA<ParkingApiException>()));
  });
  testWidgets('ParkLink reuses original login card and exposes self-registration', (tester) async {
    final repo = ParkingRepository();
    await tester.pumpWidget(ParkLinkApp(repository: repo)); await tester.pumpAndSettle();
    expect(find.text('Inicio de sesión'), findsOneWidget); expect(find.text('Crear una cuenta'), findsOneWidget);
    await tester.ensureVisible(find.text('Crear una cuenta')); await tester.tap(find.text('Crear una cuenta')); await tester.pumpAndSettle();
    expect(find.text('Crear cuenta'), findsWidgets); expect(find.text('También quiero publicar estacionamientos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
