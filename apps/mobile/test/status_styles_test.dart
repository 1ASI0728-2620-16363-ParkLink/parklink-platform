import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/ui/core/status_styles.dart';

void main() {
  test('translates service statuses to Spanish labels', () {
    expect(statusLabel('PROGRAMADO'), 'Programado');
    expect(statusLabel('EN_RECORRIDO'), 'En recorrido');
    expect(statusLabel('FINALIZADO'), 'Finalizado');
  });

  testWidgets('renders a status pill', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusPill(status: 'EN_RUTA')),
      ),
    );
    expect(find.text('En ruta'), findsOneWidget);
  });
}
