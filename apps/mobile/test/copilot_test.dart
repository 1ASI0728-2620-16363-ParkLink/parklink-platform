import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_driver/data/repositories/parking_repository.dart';
import 'package:mobile_driver/ui/core/copilot_activation_surface.dart';
import 'package:mobile_driver/ui/features/parking/view_models/copilot_view_model.dart';
import 'package:mobile_driver/ui/features/parking/views/copilot_sheet.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('double tap opens Copilot without consuming child taps', (tester) async {
    var opened = 0, tapped = 0;
    await tester.pumpWidget(MaterialApp(home: CopilotActivationSurface(onActivate: () => opened++, child: Scaffold(body: Center(child: TextButton(onPressed: () => tapped++, child: const Text('Map area')))))));
    await tester.tap(find.text('Map area')); await tester.pump(const Duration(milliseconds: 100)); await tester.tap(find.text('Map area')); await tester.pump();
    expect(opened, 1); expect(tapped, 2);
  });
  testWidgets('screen reader double tap remains reserved for accessibility', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(accessibleNavigation: true), child: CopilotActivationSurface(onActivate: () => opened++, child: const Scaffold(body: Center(child: Text('Area')))))));
    await tester.tap(find.text('Area')); await tester.tap(find.text('Area')); expect(opened, 0);
  });
  test('view model requests nearest/cheapest help but never silently confirms', () async {
    final paths = <String>[];
    final repo = ParkingRepository(client: MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/copilot/chat') {
        final body = jsonDecode(request.body) as Map<String, dynamic>; expect(body['message'], 'Reserva el más barato'); expect(body.containsKey('requestId'), isTrue);
        return http.Response(jsonEncode({'conversationId': 'conversation-1', 'engine': 'opencode', 'message': 'Revisa tu propuesta.', 'proposal': {'confirmationId': 'confirmation-1', 'summary': {'amount': 750}}}), 201);
      }
      throw StateError('Unexpected operation');
    }));
    final vm = CopilotViewModel(repo); await vm.send('Reserva el más barato');
    expect(paths, ['/copilot/chat']); expect(vm.entries.length, 2); expect(vm.error, isNull);
    expect(vm.completedConfirmations, isEmpty); vm.dispose();
  });
  testWidgets('Copilot sheet reports unavailable OpenCode and keeps a visible close action', (tester) async {
    final repo = ParkingRepository(client: MockClient((request) async => http.Response(jsonEncode({'runtimeReady': true, 'inferenceEnabled': false}), 200)));
    final vm = CopilotViewModel(repo);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CopilotSheet(viewModel: vm)))); await tester.pumpAndSettle();
    expect(find.text('Copilot'), findsOneWidget); expect(find.byTooltip('Cerrar asistente'), findsOneWidget);
    expect(find.text('OpenCode no disponible en este momento'), findsOneWidget); expect(tester.takeException(), isNull);
    vm.dispose();
  });
}
