import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_driver/ui/core/organic_route_map.dart';

void main() {
  testWidgets('renders an empty map without a default location', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OrganicRouteMap(routes: [])),
      ),
    );

    expect(find.text('Sin rutas ni vehículos para mostrar'), findsOneWidget);
  });

  testWidgets('renders the vehicle marker at a real position', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrganicRouteMap(
            routes: [],
            vehicles: [
              MapVehicleVisual(
                id: 'vehicle',
                point: LatLng(1, 1),
                heading: 90,
                label: 'Vehicle position',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('vehicle-marker')), findsOneWidget);
    expect(find.bySemanticsLabel('Vehicle position'), findsOneWidget);
  });

  testWidgets('renders the low-poly car marker when requested', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrganicRouteMap(
            routes: [],
            vehicles: [
              MapVehicleVisual(
                id: 'admin-vehicle',
                point: LatLng(1, 1),
                heading: 90,
                label: 'Admin vehicle position',
                useCarMarker: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('low-poly-vehicle')), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-marker')), findsNothing);
  });

  testWidgets('places zoom controls at the requested bottom inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrganicRouteMap(
            routes: [],
            showEmptyMap: true,
            zoomControlsBottomInset: 16,
          ),
        ),
      ),
    );
    await tester.pump();

    final mapBottom = tester.getBottomRight(find.byType(OrganicRouteMap)).dy;
    final controlsBottom = tester.getBottomRight(find.byTooltip('Alejar')).dy;

    expect(mapBottom - controlsBottom, 16);
  });
}
