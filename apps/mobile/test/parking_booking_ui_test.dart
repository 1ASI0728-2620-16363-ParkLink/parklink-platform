import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/data/repositories/parking_repository.dart';
import 'package:mobile_driver/domain/models/parking_space.dart';
import 'package:mobile_driver/ui/features/parking/views/parking_widgets.dart';
import 'package:mobile_driver/ui/features/parking/views/parklink_app.dart';

const space = ParkingSpace(
  id: 'space',
  revision: 1,
  title: 'Garage',
  address: 'Lima',
  latitude: -12,
  longitude: -77,
  hourlyRate: 750,
  description: 'Test',
  features: [],
);

void main() {
  testWidgets('reserve action occupies the full result card width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ParkingResultCard(space: space, onReserve: () {}),
            ),
          ),
        ),
      ),
    );
    final button = tester.getSize(
      find.widgetWithText(FilledButton, 'Reservar'),
    );
    expect(button.width, 360);
  });

  testWidgets('confirmation appears only for confirmed reservations', (
    tester,
  ) async {
    final repo = ParkingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSheet(
            repository: repo,
            space: space,
            reservation: const {
              'code': 'ABC',
              'amount': 750,
              'status': 'PENDING_PAYMENT',
              'expires_at': '2030-01-01T12:00:00Z',
            },
          ),
        ),
      ),
    );
    expect(find.text('Reserva confirmada'), findsNothing);
    expect(find.text('Probar rechazo en sandbox'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentSheet(
            key: const ValueKey('confirmed'),
            repository: repo,
            space: space,
            reservation: const {
              'code': 'ABC',
              'amount': 750,
              'status': 'CONFIRMED',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reserva confirmada'), findsOneWidget);
    expect(find.text('Cómo llegar'), findsOneWidget);
    repo.dispose();
  });
}
