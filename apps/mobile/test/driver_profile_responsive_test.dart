import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/ui/core/app_emergency_sheet.dart';
import 'package:mobile_driver/ui/core/app_theme.dart';
import 'package:mobile_driver/ui/features/driver/views/driver_shell_screen.dart';

void main() {
  testWidgets('vehicle card fits a narrow Android phone', (tester) async {
    await _pumpNarrow(
      tester,
      const SingleChildScrollView(
        child: VehicleProfileCard(
          plate: 'ABC-123',
          model: 'Mercedes-Benz Sprinter Ejecutiva',
          vehicleType: 'AUTO EJECUTIVO DE ALTA GAMA',
          seatCount: 18,
        ),
      ),
    );

    expect(find.text('Características'), findsOneWidget);
    expect(find.text('Mercedes-Benz Sprinter Ejecutiva'), findsOneWidget);
    expect(find.text('18 pasajeros'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emergency actions stack without overflowing', (tester) async {
    await _pumpNarrow(
      tester,
      AppEmergencySheet(onSend: () async => true, errorMessage: () => null),
    );

    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Enviar SOS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpNarrow(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 720),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
