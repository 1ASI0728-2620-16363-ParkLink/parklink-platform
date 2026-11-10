import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/domain/models/parking_space.dart';
import 'package:mobile_driver/ui/core/app_bottom_nav.dart';
import 'package:mobile_driver/ui/core/app_bottom_sheet.dart';
import 'package:mobile_driver/ui/core/app_theme.dart';
import 'package:mobile_driver/ui/features/parking/views/parking_widgets.dart';

void main() {
  testWidgets(
    'floating navigation has three accessible tabs and a separate permanent cyan search',
    (tester) async {
      var selected = 0, searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              bottomNavigationBar: AppBottomNav(
                selectedIndex: selected,
                onDestinationSelected: (value) =>
                    update(() => selected = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    label: 'Mapa',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: 'Reservas',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    label: 'Perfil',
                  ),
                ],
                trailingActions: [
                  ParkingControl(
                    icon: Icons.search,
                    label: 'Search nearby',
                    primary: true,
                    onPressed: () => searches++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final nav = tester.widget<AppBottomNav>(find.byType(AppBottomNav));
      expect(nav.destinations.length, 3);
      expect(find.text('Mapa'), findsNothing);
      expect(find.text('Reservas'), findsNothing);
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      expect(selected, 2);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.style!.backgroundColor!.resolve({}), appLime);
      expect(button.style!.foregroundColor!.resolve({}), appBlack);
      await tester.tap(find.byIcon(Icons.search));
      expect(searches, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('white sheet provides a light theme to its builder', (
    tester,
  ) async {
    Brightness? brightness;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppBottomSheet<void>(
                context: context,
                builder: (sheetContext) {
                  brightness = Theme.of(sheetContext).brightness;
                  return const Text('Sheet content');
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'result keeps photo on the left and supports small screens with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reservations = 0;
      const space = ParkingSpace(
        id: 'registered',
        revision: 1,
        title: 'Registered parking with a long name',
        address: 'Registered street address',
        latitude: -12,
        longitude: -77,
        hourlyRate: 750,
        description: '',
        features: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppSheetTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ParkingResultCard(
                  space: space,
                  verified: true,
                  distanceMeters: 150,
                  onReserve: () => reservations++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byType(ParkingPhoto)).dx,
        lessThan(tester.getTopLeft(find.text(space.title)).dx),
      );
      expect(find.text('Sin foto'), findsOneWidget);
      await tester.ensureVisible(find.text('Reservar'));
      await tester.tap(find.text('Reservar'));
      expect(reservations, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
