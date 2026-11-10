import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/domain/models/admin_records.dart';
import 'package:mobile_driver/domain/models/transport_service.dart';
import 'package:mobile_driver/ui/core/app_theme.dart';
import 'package:mobile_driver/ui/features/admin/views/dashboard/dashboard_drivers_sheet.dart';
import 'package:mobile_driver/ui/features/admin/views/dashboard/dashboard_invitations.dart';
import 'package:mobile_driver/ui/features/admin/views/dashboard/dashboard_quick_access.dart';
import 'package:mobile_driver/ui/features/admin/views/dashboard/dashboard_services.dart';
import 'package:mobile_driver/ui/features/admin/views/dashboard/dashboard_services_sheet.dart';

void main() {
  group('ActiveServicesCard', () {
    testWidgets('renders its empty state', (tester) async {
      await _pumpDashboardWidget(
        tester,
        ActiveServicesCard(
          services: const [],
          onOpenServices: () {},
          onServiceTap: (_) {},
          onDownloadReport: () {},
        ),
      );

      expect(find.text('Servicios activos'), findsOneWidget);
      expect(find.text('No hay servicios activos.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders and opens a service with a long destination', (
      tester,
    ) async {
      const destination =
          'Terminal terrestre internacional de la avenida muy larga número '
          '1234, distrito metropolitano';
      final service = TransportService(
        id: 'service-1',
        code: 'SRV-001',
        scheduledAt: DateTime(2026, 7, 25, 14, 30),
        pickupAddress: 'Almacén central',
        pickupLatitude: -12.0464,
        pickupLongitude: -77.0428,
        destinationAddress: destination,
        destinationLatitude: -12.089,
        destinationLongitude: -77.05,
        currentStatus: 'PROGRAMADO',
        driverName: 'Ana Torres',
        vehiclePlate: 'ABC-123',
      );
      TransportService? selectedService;
      var openServicesCount = 0;

      await _pumpDashboardWidget(
        tester,
        ActiveServicesCard(
          services: [service],
          onOpenServices: () => openServicesCount++,
          onServiceTap: (value) => selectedService = value,
          onDownloadReport: () {},
        ),
        width: 320,
      );

      expect(find.text('SRV-001  ·  25/07 · 14:30'), findsOneWidget);
      expect(find.text(destination), findsOneWidget);
      expect(find.text('Programado'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Servicios activos'));
      await tester.pump();

      expect(openServicesCount, 1);

      await tester.tap(find.text(destination));
      await tester.pump();

      expect(selectedService, same(service));
    });

    testWidgets('shows the icon-only PDF download action', (tester) async {
      var downloadCount = 0;

      await _pumpDashboardWidget(
        tester,
        ActiveServicesCard(
          services: const [],
          onOpenServices: () {},
          onServiceTap: (_) {},
          onDownloadReport: () => downloadCount++,
        ),
      );

      final button = find.byKey(const Key('download-services-report'));
      expect(button, findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(find.text('Descargar reporte PDF'), findsNothing);

      final iconButton = tester.widget<IconButton>(button);
      expect(iconButton.style?.backgroundColor?.resolve({}), appWhite);
      expect(iconButton.style?.foregroundColor?.resolve({}), appBlack);
      expect(iconButton.style?.shape?.resolve({}), isA<CircleBorder>());

      await tester.tap(button);
      await tester.pump();
      expect(downloadCount, 1);
    });
  });

  testWidgets('QuickAccessGrid fits all service metrics on a narrow phone', (
    tester,
  ) async {
    await _pumpDashboardWidget(
      tester,
      QuickAccessGrid(
        drivers: const [],
        activeServices: 8,
        completedServices: 14,
        cancelledServices: 2,
        onOpenDrivers: () {},
        onInviteDriver: () {},
      ),
      width: 320,
    );

    expect(find.text('Activos'), findsOneWidget);
    expect(find.text('Completados'), findsOneWidget);
    expect(find.text('Cancelados'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
    expect(find.text('Servicios'), findsNothing);
    expect(find.text('92%'), findsNWidgets(2));
    expect(find.text('Operatividad'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('SentInvitationsSection', () {
    testWidgets('renders its empty state', (tester) async {
      await _pumpDashboardWidget(
        tester,
        const SentInvitationsSection(invitations: []),
      );

      expect(find.text('No hay invitaciones enviadas'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('simplifies a single invitation', (tester) async {
      final invitation = InvitationRecord(
        id: 'invitation-1',
        email: 'lucia.ramos@example.com',
        driverName: 'Lucía Ramos',
        status: 'PENDING',
        invitationCode: 'INV-7284',
        createdAt: DateTime(2026, 7, 24, 9, 15),
      );

      await _pumpDashboardWidget(
        tester,
        SentInvitationsSection(invitations: [invitation]),
        width: 320,
      );

      expect(find.text('Lucía Ramos'), findsOneWidget);
      expect(find.text('lucia.ramos@example.com'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.textContaining('INV-7284'), findsNothing);
      expect(find.textContaining('24/07/2026'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'multiple invitations expand and collapse from every toggle target',
      (tester) async {
        final invitations = [
          InvitationRecord(
            id: 'invitation-oldest',
            email: 'oldest@example.com',
            driverName: 'Invitación más antigua',
            status: 'EXPIRED',
            invitationCode: 'INV-1001',
            createdAt: DateTime(2026, 7, 22, 9),
          ),
          InvitationRecord(
            id: 'invitation-newest',
            email: 'newest@example.com',
            driverName: 'Invitación más reciente',
            status: 'PENDING',
            invitationCode: 'INV-1003',
            createdAt: DateTime(2026, 7, 24, 9),
          ),
          InvitationRecord(
            id: 'invitation-middle',
            email: 'middle@example.com',
            driverName: 'Invitación intermedia',
            status: 'ACCEPTED',
            invitationCode: 'INV-1002',
            createdAt: DateTime(2026, 7, 23, 9),
          ),
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        await _pumpDashboardWidget(
          tester,
          SentInvitationsSection(invitations: invitations),
          width: 320,
        );

        final section = find.byType(SentInvitationsSection);
        final compactHeight = tester.getSize(section).height;
        expect(find.text('Invitación más reciente'), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Invitaciones enviadas'));
        await tester.pumpAndSettle();
        final headerExpandedHeight = tester.getSize(section).height;
        expect(headerExpandedHeight, greaterThan(compactHeight));
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
        await tester.pumpAndSettle();
        final arrowCollapsedHeight = tester.getSize(section).height;
        expect(arrowCollapsedHeight, lessThan(headerExpandedHeight));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Invitación más reciente'));
        await tester.pumpAndSettle();
        final cardExpandedHeight = tester.getSize(section).height;
        expect(cardExpandedHeight, greaterThan(arrowCollapsedHeight));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Invitación más reciente'));
        await tester.pumpAndSettle();
        expect(tester.getSize(section).height, lessThan(cardExpandedHeight));
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('DriversListSheet filters real drivers', (tester) async {
    const drivers = [
      DriverRecord(
        id: 'driver-1',
        fullName: 'Carlos Mendoza',
        documentNumber: '76543210',
        status: 'ACTIVE',
      ),
      DriverRecord(
        id: 'driver-2',
        fullName: 'Rosa Quispe',
        documentNumber: '45871236',
        status: 'ACTIVE',
      ),
      DriverRecord(
        id: 'driver-3',
        fullName: 'Pedro León',
        documentNumber: '41726358',
        status: 'INACTIVE',
      ),
    ];
    final toggledDrivers = <DriverRecord>[];

    await _pumpDashboardWidget(
      tester,
      DriversListSheet(
        drivers: drivers,
        onToggleDriverStatus: toggledDrivers.add,
      ),
    );

    expect(find.text('Carlos Mendoza'), findsOneWidget);
    expect(find.text('Rosa Quispe'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Rosa');
    await tester.pump();

    expect(find.text('Carlos Mendoza'), findsNothing);
    expect(find.text('Rosa Quispe'), findsOneWidget);

    await tester.tap(find.byTooltip('Desactivar driver'));
    await tester.pump();

    expect(toggledDrivers, hasLength(1));
    expect(toggledDrivers.first, same(drivers[1]));

    await tester.enterText(find.byType(TextField), 'Pedro');
    await tester.pump();
    await tester.tap(find.byTooltip('Activar driver'));
    await tester.pump();

    expect(toggledDrivers, hasLength(2));
    expect(toggledDrivers.last, same(drivers[2]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('DriversListSheet hides status actions in read-only mode', (
    tester,
  ) async {
    await _pumpDashboardWidget(
      tester,
      const DriversListSheet(
        drivers: [
          DriverRecord(
            id: 'driver-1',
            fullName: 'Carlos Mendoza',
            documentNumber: '76543210',
            status: 'ACTIVE',
          ),
        ],
      ),
    );

    expect(find.byTooltip('Desactivar driver'), findsNothing);
    expect(find.byTooltip('Activar driver'), findsNothing);
  });

  testWidgets('Asignar shows only for PROGRAMADO without a driver', (
    tester,
  ) async {
    final programado = TransportService(
      id: 'service-1',
      code: 'SRV-001',
      scheduledAt: DateTime(2026, 7, 25, 14, 30),
      pickupAddress: 'Almacén central',
      pickupLatitude: -12.0464,
      pickupLongitude: -77.0428,
      destinationAddress: 'Terminal principal',
      destinationLatitude: -12.089,
      destinationLongitude: -77.05,
      currentStatus: 'PROGRAMADO',
      driverName: null,
      vehiclePlate: null,
    );
    final alreadyAssigned = TransportService(
      id: 'service-2',
      code: 'SRV-002',
      scheduledAt: DateTime(2026, 7, 25, 15, 30),
      pickupAddress: 'Almacén central',
      pickupLatitude: -12.0464,
      pickupLongitude: -77.0428,
      destinationAddress: 'Terminal norte',
      destinationLatitude: -12.02,
      destinationLongitude: -77.05,
      currentStatus: 'PROGRAMADO',
      driverName: 'Ana Torres',
      vehiclePlate: 'ABC-123',
    );
    final inProgress = TransportService(
      id: 'service-3',
      code: 'SRV-003',
      scheduledAt: DateTime(2026, 7, 25, 16, 30),
      pickupAddress: 'Almacén central',
      pickupLatitude: -12.0464,
      pickupLongitude: -77.0428,
      destinationAddress: 'Terminal sur',
      destinationLatitude: -12.15,
      destinationLongitude: -77.02,
      currentStatus: 'EN_RUTA',
      driverName: null,
      vehiclePlate: null,
    );
    final assignedServices = <TransportService>[];

    await _pumpDashboardWidget(
      tester,
      ServicesListSheet(
        services: [programado, alreadyAssigned, inProgress],
        onViewService: (_) {},
        onCancelService: (_) {},
        onAssignService: assignedServices.add,
      ),
    );

    expect(find.text('Asignar'), findsOneWidget);
    await tester.tap(find.text('Asignar'));
    await tester.pump();

    expect(assignedServices, hasLength(1));
    expect(assignedServices.single, same(programado));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ServicesListSheet searches, cancels, and opens a service', (
    tester,
  ) async {
    final services = [
      _service(id: 'service-1', code: 'SRV-001'),
      _service(id: 'service-2', code: 'SRV-002'),
    ];
    TransportService? selectedService;
    TransportService? cancelledService;

    await _pumpDashboardWidget(
      tester,
      ServicesListSheet(
        services: services,
        onViewService: (service) => selectedService = service,
        onCancelService: (service) => cancelledService = service,
        onAssignService: (_) {},
      ),
    );

    expect(find.text('SRV-001'), findsOneWidget);
    expect(find.text('SRV-002'), findsOneWidget);
    expect(find.text('Crear servicio'), findsNothing);
    expect(find.text('Terminal principal'), findsNothing);
    expect(find.text('Ver'), findsNothing);
    expect(find.text('Cancelar'), findsNothing);

    await tester.enterText(find.byType(TextField), 'SRV-002');
    await tester.pump();

    expect(find.text('SRV-001'), findsNothing);
    expect(find.text('SRV-002'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Ver servicio'));
    await tester.pump();

    expect(selectedService, same(services[1]));

    await tester.tap(find.byTooltip('Cancelar servicio'));
    await tester.pump();

    expect(cancelledService, same(services[1]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('QuickAccessGrid renders and invokes both actions', (
    tester,
  ) async {
    var driversTapCount = 0;
    var inviteTapCount = 0;
    const driver = DriverRecord(
      id: 'driver-1',
      fullName: 'Carlos Mendoza',
      documentNumber: '76543210',
      status: 'ACTIVE',
      availabilityStatus: 'DISPONIBLE',
    );
    await _pumpDashboardWidget(
      tester,
      QuickAccessGrid(
        drivers: const [driver],
        activeServices: 4,
        completedServices: 3,
        cancelledServices: 1,
        onOpenDrivers: () => driversTapCount++,
        onInviteDriver: () => inviteTapCount++,
      ),
      width: 320,
    );

    expect(find.text('Drivers'), findsOneWidget);
    expect(find.text('Servicios'), findsNothing);
    expect(find.text('Activos'), findsOneWidget);
    expect(find.text('Completados'), findsOneWidget);
    expect(find.text('Cancelados'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
    expect(find.text('94%'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Mandar invitación'));
    await tester.tap(find.text('Drivers'));
    await tester.pump();

    expect(driversTapCount, 1);
    expect(inviteTapCount, 1);
  });
}

TransportService _service({required String id, required String code}) {
  return TransportService(
    id: id,
    code: code,
    scheduledAt: DateTime(2026, 7, 25, 14, 30),
    pickupAddress: 'Almacén central',
    pickupLatitude: -12.0464,
    pickupLongitude: -77.0428,
    destinationAddress: 'Terminal principal',
    destinationLatitude: -12.089,
    destinationLongitude: -77.05,
    currentStatus: 'PROGRAMADO',
    driverName: 'Ana Torres',
    vehiclePlate: 'ABC-123',
  );
}

Future<void> _pumpDashboardWidget(
  WidgetTester tester,
  Widget child, {
  double width = 390,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}
