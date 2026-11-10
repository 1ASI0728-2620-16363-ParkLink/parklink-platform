import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_driver/data/services/road_routing_service.dart';
import 'package:mobile_driver/ui/core/address_autocomplete_field.dart';

void main() {
  testWidgets('selecting a Maps suggestion fills the address and point', (
    tester,
  ) async {
    final controller = TextEditingController();
    LatLng? selectedPoint;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            controller: controller,
            label: 'Origen',
            icon: Icons.trip_origin_rounded,
            routingService: const _FakeRoutingService(),
            validator: (_) => null,
            onPointChanged: (point) => selectedPoint = point,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Jorge Chavez');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Aeropuerto Internacional Jorge Chávez'), findsOneWidget);

    await tester.tap(find.text('Aeropuerto Internacional Jorge Chávez'));
    await tester.pumpAndSettle();

    expect(controller.text, 'Av. Elmer Faucett s/n, Callao');
    expect(selectedPoint, const LatLng(-12.0219, -77.1143));
    expect(tester.takeException(), isNull);
  });
}

class _FakeRoutingService extends RoadRoutingService {
  const _FakeRoutingService();

  @override
  Future<List<AddressSuggestion>> addressSuggestions(String query) async {
    return const [
      AddressSuggestion(
        label: 'Aeropuerto Internacional Jorge Chávez, Callao',
        placeId: 'airport',
      ),
    ];
  }

  @override
  Future<AddressSuggestion> resolveSuggestion(
    AddressSuggestion suggestion,
  ) async {
    return const AddressSuggestion(
      label: 'Av. Elmer Faucett s/n, Callao',
      placeId: 'airport',
      point: LatLng(-12.0219, -77.1143),
    );
  }
}
