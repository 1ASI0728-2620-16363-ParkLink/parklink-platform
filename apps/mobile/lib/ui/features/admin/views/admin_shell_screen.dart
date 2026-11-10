import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../data/services/road_routing_service.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../domain/models/admin_records.dart';
import '../../../../domain/models/in_app_notification.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../domain/models/transport_service.dart';
import '../../../core/address_autocomplete_field.dart';
import '../../../core/app_bottom_sheet.dart';
import '../../../core/app_scope.dart';
import '../../../core/app_bottom_nav.dart';
import '../../../core/app_theme.dart';
import '../../../core/map_theme.dart';
import '../../../core/push_navigation.dart';
import '../../../core/date_formats.dart';
import '../../../core/organic_route_map.dart';
import '../../../core/status_styles.dart';
import '../view_models/admin_view_model.dart';
import 'dashboard/dashboard_common.dart';
import 'dashboard/dashboard_drivers_sheet.dart';
import 'dashboard/dashboard_invitations.dart';
import 'dashboard/dashboard_quick_access.dart';
import 'dashboard/map_unit_sheet.dart';
import 'dashboard/dashboard_services.dart';
import 'dashboard/dashboard_services_sheet.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({this.onLoggedOut, super.key});

  final VoidCallback? onLoggedOut;

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 1;
  bool _sheetOpen = false;
  bool _creatingRoute = false;
  String? _selectedRouteId;

  /// Observador: sólo mira. Sin crear, sin editar y sin emergencias.
  bool _soloLectura = false;
  bool _esAdministrador = false;

  /// Conductor que el mapa debe centrar tras tocar "Ubicar".
  String? _ubicarDriverId;
  LatLng? _draftPickup;
  LatLng? _draftDestination;
  late final AdminViewModel _viewModel;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scope = AppScope.of(context, listen: false);
    _soloLectura = scope.sessionStore.user?.role == 'VIEWER';
    // El tiempo de llegada es solo para el administrador: el observador mira la
    // operacion, no la conduce, y cada consulta a Google se cobra.
    _esAdministrador = scope.sessionStore.user?.role == 'ADMIN';
    _viewModel = AdminViewModel(
      adminRepository: scope.adminRepository,
      authRepository: scope.authRepository,
      notificationRepository: scope.notificationRepository,
    );
    unawaited(_viewModel.load());
    _viewModel.setLiveUpdatesEnabled(true);
    pendingAssignmentRequestId.addListener(_atenderPushPendiente);
    // El push pudo llegar antes de que existiera esta pantalla.
    if (pendingAssignmentRequestId.value != null) _atenderPushPendiente();
  }

  /// Abre el formulario de asignación de la solicitud que llegó por push.
  ///
  /// El aviso trae sólo el id, así que se busca la notificación equivalente en
  /// la bandeja —el backend crea las dos a la vez— y se reutiliza el mismo
  /// camino que al tocar el banner dentro de la app.
  Future<void> _atenderPushPendiente() async {
    final requestId = pendingAssignmentRequestId.value;
    if (requestId == null || _sheetOpen) return;
    pendingAssignmentRequestId.value = null;

    await _viewModel.loadNotifications();
    if (!mounted) return;
    final notificacion = _viewModel.notifications
        .where((item) => item.requestId == requestId)
        .firstOrNull;
    if (notificacion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La solicitud ya no está disponible.')),
      );
      return;
    }
    await _openRequestNotification(notificacion);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pendingAssignmentRequestId.removeListener(_atenderPushPendiente);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          final requestNotification = _viewModel.serviceRequestNotification;
          return Stack(
            children: [
              IndexedStack(
                index: _index,
                children: [
                  _AdminDashboard(
                    viewModel: _viewModel,
                    onLogout: _logout,
                    onRouteSelected: _openRouteFromDashboard,
                    onOpenDrivers: _openDrivers,
                    onInviteDriver: _soloLectura ? null : _openInviteDriver,
                    onOpenServices: _openServices,
                    onDownloadReport: _downloadServicesReport,
                    showInvitations: !_soloLectura,
                  ),
                  _AdminMapTab(
                    viewModel: _viewModel,
                    esAdministrador: _esAdministrador,
                    hideRoutes: _creatingRoute,
                    selectedRouteId: _selectedRouteId,
                    draftPickup: _draftPickup,
                    draftDestination: _draftDestination,
                    onRouteSelected: _openRouteDetails,
                    ubicarDriverId: _ubicarDriverId,
                    zoomControlsBottomInset: 16,
                  ),
                ],
              ),
              if (requestNotification != null)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 12,
                  left: 16,
                  right: 16,
                  child: _AdminRequestNotificationBanner(
                    notification: requestNotification,
                    onTap: () => _openRequestNotification(requestNotification),
                    onDismiss: _viewModel.dismissServiceRequestNotification,
                  ),
                ),
              if (_viewModel.isLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x55000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (_soloLectura && !_sheetOpen)
                Positioned(
                  left: 16,
                  bottom: MediaQuery.paddingOf(context).bottom + 16,
                  child: Row(
                    children: [
                      _viewerDestinationButton(
                        index: 0,
                        tooltip: 'Panel',
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                      ),
                      const SizedBox(width: 10),
                      _viewerDestinationButton(
                        index: 1,
                        tooltip: 'Mapa',
                        icon: Icons.radar_outlined,
                        selectedIcon: Icons.radar_rounded,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: _sheetOpen || _soloLectura
          ? null
          : AppBottomNav(
              selectedIndex: _index,
              onDestinationSelected: _selectDestination,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Panel',
                ),
                NavigationDestination(
                  icon: Icon(Icons.radar_outlined),
                  selectedIcon: Icon(Icons.radar_rounded),
                  label: 'Mapa',
                ),
              ],
              trailingActions: [
                SizedBox.square(
                  dimension: 68,
                  child: FloatingActionButton(
                    heroTag: 'create-route',
                    tooltip: 'Crear ruta',
                    onPressed: _openCreateRoute,
                    backgroundColor: appLime,
                    foregroundColor: appWhite,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.add_road_rounded, size: 34),
                  ),
                ),
                SizedBox.square(
                  dimension: 68,
                  child: FloatingActionButton(
                    heroTag: 'invite-driver',
                    tooltip: 'Mandar invitación',
                    onPressed: _openInviteDriver,
                    backgroundColor: appWhite,
                    foregroundColor: appBlack,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: const BorderSide(color: Color(0xFFD8D8D8)),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, size: 34),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _viewerDestinationButton({
    required int index,
    required String tooltip,
    required IconData icon,
    required IconData selectedIcon,
  }) {
    final selected = _index == index;
    return Semantics(
      selected: selected,
      child: SizedBox.square(
        dimension: 68,
        child: FloatingActionButton(
          key: ValueKey('viewer-nav-$index'),
          heroTag: 'viewer-nav-$index',
          tooltip: tooltip,
          onPressed: () => _selectDestination(index),
          backgroundColor: selected ? appLime : appWhite,
          foregroundColor: selected ? appWhite : appBlack,
          elevation: 8,
          shape: const CircleBorder(side: BorderSide(color: Color(0x33000000))),
          child: Icon(selected ? selectedIcon : icon, size: 34),
        ),
      ),
    );
  }

  void _selectDestination(int value) {
    setState(() => _index = value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _viewModel.setLiveUpdatesEnabled(_appActive);
  }

  Future<void> _openCreateRoute() async {
    if (_sheetOpen) return;
    _viewModel.clearFeedback();
    setState(() {
      _index = 1;
      _draftPickup = null;
      _draftDestination = null;
      _sheetOpen = true;
      _creatingRoute = true;
    });
    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        child: _CreateRouteSheet(
          viewModel: _viewModel,
          onPickupPointChanged: (point) {
            if (mounted) setState(() => _draftPickup = point);
          },
          onDestinationPointChanged: (point) {
            if (mounted) setState(() => _draftDestination = point);
          },
        ),
      ),
      backgroundColor: appWhite,
      elevation: 0,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      clipBehavior: Clip.antiAlias,
    );
    await controller.closed;
    if (mounted) {
      setState(() {
        _draftPickup = null;
        _draftDestination = null;
        _sheetOpen = false;
        _creatingRoute = false;
      });
    }
  }

  Future<void> _openInviteDriver() async {
    _viewModel.clearFeedback();
    final invited = await _showAdminSheet<bool>(
      (_) => _InviteDriverSheet(viewModel: _viewModel),
    );
    if (mounted && (invited ?? false)) setState(() => _index = 0);
  }

  Future<void> _openDrivers() async {
    final driver = await _showAdminSheet<DriverRecord>(
      (sheetContext) => ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => DriversListSheet(
          drivers: _viewModel.drivers,
          liveLocations: _viewModel.liveDrivers,
          onRequestLocation: (driver) async {
            // "Ubicar" tiene que llevar al conductor en el mapa, no sólo pedir
            // su posición: se cierra la hoja, se pasa a la pestaña del mapa y
            // se centra en él. La solicitud se envía igual, para refrescar la
            // posición si estuviera vieja.
            Navigator.of(sheetContext).pop();
            if (mounted) {
              setState(() {
                _ubicarDriverId = driver.id;
                _index = 1;
              });
            }
            final sent = await _viewModel.requestDriverLocation(driver.id);
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  sent
                      ? 'Solicitud enviada a ${driver.fullName}.'
                      : _friendlyAdminError(
                          _viewModel.errorMessage ??
                              'No se pudo solicitar la ubicación.',
                        ),
                ),
              ),
            );
          },
          requestingDriver: _viewModel.isRequestingDriver,
          onToggleDriverStatus: _soloLectura
              ? null
              : (driver) => Navigator.of(sheetContext).pop(driver),
        ),
      ),
    );
    if (driver != null) await _viewModel.toggleDriverStatus(driver);
  }

  Future<void> _openServices() async {
    final services = [..._viewModel.services]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final result =
        await _showAdminSheet<
          ({bool cancel, bool assign, TransportService service})
        >(
          (sheetContext) => ServicesListSheet(
            services: services,
            onViewService: (service) => Navigator.of(
              sheetContext,
            ).pop((cancel: false, assign: false, service: service)),
            onCancelService: (service) => Navigator.of(
              sheetContext,
            ).pop((cancel: true, assign: false, service: service)),
            onAssignService: (service) => Navigator.of(
              sheetContext,
            ).pop((cancel: false, assign: true, service: service)),
          ),
        );
    if (!mounted || result == null) return;

    if (result.cancel) {
      await _viewModel.cancelService(result.service.id);
    } else if (result.assign) {
      await _openAssignSheet(result.service);
    } else {
      _openRouteFromDashboard(result.service);
    }
  }

  Future<void> _openAssignSheet(TransportService service) async {
    _viewModel.clearFeedback();
    await _viewModel.refreshAssignmentData(service.id);
    if (!mounted) return;
    final assigned = await _showAdminSheet<bool>(
      (sheetContext) => ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) =>
            _AssignServiceSheet(service: service, viewModel: _viewModel),
      ),
    );
    if (mounted && (assigned ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _viewModel.message ?? 'Servicio asignado correctamente.',
          ),
        ),
      );
    }
  }

  Future<void> _openRequestNotification(InAppNotification notification) async {
    if (_sheetOpen) return;
    final service = await _viewModel.openServiceRequestNotification(
      notification,
    );
    if (!mounted) return;
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyAdminError(
              _viewModel.notificationError ??
                  'La solicitud ya no está disponible.',
            ),
          ),
        ),
      );
      return;
    }
    await _openAssignSheet(service);
  }

  Future<void> _downloadServicesReport() async {
    final path = await _viewModel.downloadServicesReport();
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyAdminError(
              _viewModel.errorMessage ?? 'No se pudo generar el reporte PDF.',
            ),
          ),
        ),
      );
      return;
    }

    final result = await OpenFilex.open(path, type: 'application/pdf');
    if (!mounted || result.type == ResultType.done) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo abrir el PDF: ${result.message}')),
    );
  }

  void _openRouteFromDashboard(TransportService service) {
    setState(() => _index = 1);
    _openRouteDetails(service);
  }

  Future<void> _openRouteDetails(TransportService service) async {
    if (_sheetOpen) return;
    final routeIndex = _viewModel.services.indexWhere(
      (route) => route.id == service.id,
    );
    final routeColor =
        _routePalette[(routeIndex < 0 ? 0 : routeIndex) % _routePalette.length];
    final liveMatches = _viewModel.liveVehicles.where(
      (vehicle) => vehicle.serviceId == service.id,
    );
    setState(() {
      _selectedRouteId = service.id;
      _sheetOpen = true;
    });
    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (_) => _RouteDetailsSheet(
        service: service,
        routeColor: routeColor,
        liveVehicle: liveMatches.isEmpty ? null : liveMatches.first,
      ),
      backgroundColor: appWhite,
      elevation: 0,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      clipBehavior: Clip.antiAlias,
    );
    await controller.closed;
    if (mounted) {
      setState(() {
        _selectedRouteId = null;
        _sheetOpen = false;
      });
    }
  }

  Future<T?> _showAdminSheet<T>(WidgetBuilder builder) async {
    if (_sheetOpen) return null;
    setState(() => _sheetOpen = true);
    final result = await showAppBottomSheet<T>(
      context: context,
      builder: builder,
    );
    if (mounted) setState(() => _sheetOpen = false);
    return result;
  }

  Future<void> _logout() async {
    await _viewModel.logout();
    if (mounted) widget.onLoggedOut?.call();
  }
}

const _terminalDashboardStatuses = {'CANCELADO'};

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({
    required this.viewModel,
    required this.onLogout,
    required this.onRouteSelected,
    required this.onOpenDrivers,
    required this.onInviteDriver,
    required this.onOpenServices,
    required this.onDownloadReport,
    required this.showInvitations,
  });

  final AdminViewModel viewModel;
  final Future<void> Function() onLogout;
  final ValueChanged<TransportService> onRouteSelected;
  final VoidCallback onOpenDrivers;

  /// Ausente para el observador: no invita conductores.
  final VoidCallback? onInviteDriver;
  final VoidCallback onOpenServices;
  final VoidCallback onDownloadReport;
  final bool showInvitations;

  @override
  Widget build(BuildContext context) {
    final invitations = [...viewModel.invitations]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final completedRoutes =
        viewModel.services
            .where((service) => service.currentStatus == 'FINALIZADO')
            .toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    final cancelledRoutes = viewModel.services
        .where(
          (service) =>
              _terminalDashboardStatuses.contains(service.currentStatus),
        )
        .toList();
    final activeRoutes =
        viewModel.services
            .where(
              (service) =>
                  service.currentStatus != 'FINALIZADO' &&
                  !_terminalDashboardStatuses.contains(service.currentStatus),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final hasDashboardData =
        viewModel.services.isNotEmpty ||
        viewModel.drivers.isNotEmpty ||
        invitations.isNotEmpty;
    final hasBlockingError =
        viewModel.errorMessage != null && !hasDashboardData;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 360
        ? 18.0
        : 24.0;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final headerInset =
        132.0 + ((textScale - 1).clamp(0.0, 2.0) * 64).toDouble();

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: viewModel.load,
            child: ListView(
              key: const PageStorageKey('admin-dashboard'),
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                headerInset,
                horizontalPadding,
                152,
              ),
              children: [
                if (hasBlockingError)
                  DashboardErrorCard(
                    message: _friendlyAdminError(viewModel.errorMessage!),
                    onRetry: viewModel.load,
                    expanded: true,
                  )
                else ...[
                  if (viewModel.errorMessage != null) ...[
                    DashboardErrorCard(
                      message: _friendlyAdminError(viewModel.errorMessage!),
                      onRetry: viewModel.load,
                    ),
                    const SizedBox(height: 22),
                  ],
                  QuickAccessGrid(
                    drivers: viewModel.drivers,
                    activeServices: activeRoutes.length,
                    completedServices: completedRoutes.length,
                    cancelledServices: cancelledRoutes.length,
                    onOpenDrivers: onOpenDrivers,
                    onInviteDriver: onInviteDriver,
                  ),
                  const SizedBox(height: 24),
                  ActiveServicesCard(
                    services: activeRoutes,
                    onOpenServices: onOpenServices,
                    onServiceTap: onRouteSelected,
                    onDownloadReport: onDownloadReport,
                  ),
                  if (showInvitations) ...[
                    const SizedBox(height: 28),
                    SentInvitationsSection(invitations: invitations),
                  ],
                ],
                const SizedBox(height: 32),
                ValueListenableBuilder<MapTheme>(
                  valueListenable: mapThemeController,
                  builder: (context, mapTheme, _) => OutlinedButton.icon(
                    onPressed: () => showMapThemePicker(context),
                    style: _adminActionButtonStyle,
                    icon: const Icon(Icons.layers_outlined),
                    label: Text('Tema del mapa: ${mapTheme.label}'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onLogout,
                  style: _adminActionButtonStyle,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ControlCenterHeader(adminName: viewModel.adminName),
          ),
        ],
      ),
    );
  }
}

const _routePalette = [
  appLime,
  Color(0xFF38BDF8),
  Color(0xFFF472B6),
  Color(0xFFFBBF24),
  Color(0xFFA78BFA),
];

class _AdminRequestNotificationBanner extends StatelessWidget {
  const _AdminRequestNotificationBanner({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  final InAppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      button: true,
      label:
          '${notification.title}. ${notification.message}. Toca para asignar un conductor.',
      child: Material(
        color: appLime,
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: appBlack),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        notification.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appBlack,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        notification.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF30302C),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Asignar',
                  style: TextStyle(
                    color: appBlack,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                IconButton(
                  tooltip: 'Descartar aviso',
                  onPressed: onDismiss,
                  color: appBlack,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _vehicleTypes = <({String value, String label, int minSeats})>[
  (
    value: 'AUTO_EXECUTIVO',
    label: 'Auto / SUV Ejecutivo de Alta Gama',
    minSeats: 4,
  ),
  (value: 'AUTO_SEDAN', label: 'Auto / SUV Sedán', minSeats: 4),
  (value: 'VAN', label: 'Van', minSeats: 18),
  (value: 'OMNIBUS', label: 'Ómnibus', minSeats: 40),
];

int _minSeatsFor(String? vehicleType) => _vehicleTypes
    .firstWhere(
      (type) => type.value == vehicleType,
      orElse: () => _vehicleTypes.first,
    )
    .minSeats;

class _AdminMapTab extends StatefulWidget {
  const _AdminMapTab({
    required this.viewModel,
    required this.esAdministrador,
    required this.hideRoutes,
    required this.selectedRouteId,
    required this.draftPickup,
    required this.draftDestination,
    required this.onRouteSelected,
    required this.zoomControlsBottomInset,
    this.ubicarDriverId,
  });

  final AdminViewModel viewModel;

  /// Solo el administrador ve el tiempo restante de una unidad en camino.
  final bool esAdministrador;
  final bool hideRoutes;
  final String? selectedRouteId;
  final LatLng? draftPickup;
  final LatLng? draftDestination;
  final Future<void> Function(TransportService service) onRouteSelected;
  final double zoomControlsBottomInset;

  /// Conductor a centrar tras tocar "Ubicar".
  final String? ubicarDriverId;

  @override
  State<_AdminMapTab> createState() => _AdminMapTabState();
}

class _AdminMapTabState extends State<_AdminMapTab> {
  /// Marcador del conductor que se pidió ubicar.
  ///
  /// Aparece como vehículo si está en servicio y como presencia si no lo está,
  /// así que se buscan las dos formas. Devuelve null si todavía no reportó
  /// posición: ahí no hay nada que centrar.
  /// Abre el resumen de la unidad tocada en el mapa.
  ///
  /// Al mapa llegan dos clases de marcador y hay que distinguirlas por el id:
  /// las unidades con servicio en curso vienen de `liveVehicles` y traen placa
  /// y codigo de servicio; las de conductores disponibles vienen de
  /// `liveDrivers`, se marcan con el prefijo `driver-presence:` y su vehiculo
  /// hay que buscarlo en el padron.
  void _mostrarResumenDeUnidad(MapVehicleVisual marcador) {
    const prefijoPresencia = 'driver-presence:';
    if (marcador.id.startsWith(prefijoPresencia)) {
      final driverId = marcador.id.substring(prefijoPresencia.length);
      final vivo = widget.viewModel.liveDrivers
          .where((item) => item.driverId == driverId)
          .firstOrNull;
      if (vivo == null) return;
      final ficha = widget.viewModel.drivers
          .where((item) => item.id == driverId)
          .firstOrNull;
      showMapUnitSheet(
        context,
        MapUnitSummary(
          driverName: vivo.driverName.isEmpty
              ? (ficha?.fullName ?? 'Conductor')
              : vivo.driverName,
          estado: vivo.available ? 'Disponible, sin servicio' : 'No disponible',
          // DriverRecord no trae el vehiculo vinculado, y un conductor sin
          // servicio no tiene unidad en vivo de donde deducirlo: se muestra
          // sin placa en vez de arriesgar una equivocada.
          phone: ficha?.phone,
        ),
      );
      return;
    }

    final vehiculo = widget.viewModel.liveVehicles
        .where(
          (item) =>
              '${item.vehicleId}:${item.serviceId ?? 'unassigned'}' ==
              marcador.id,
        )
        .firstOrNull;
    if (vehiculo == null) return;
    final ficha = vehiculo.driverId == null
        ? null
        : widget.viewModel.drivers
              .where((item) => item.id == vehiculo.driverId)
              .firstOrNull;
    showMapUnitSheet(
      context,
      MapUnitSummary(
        driverName: vehiculo.driverName ?? ficha?.fullName ?? 'Sin conductor',
        estado: vehiculo.status,
        tiempoDeLlegada: _tiempoHastaElDestino(vehiculo),
        plate: vehiculo.vehiclePlate,
        vehicleModel: widget.viewModel.vehicles
            .where((item) => item.id == vehiculo.vehicleId)
            .firstOrNull
            ?.model,
        serviceCode: vehiculo.serviceCode,
        phone: ficha?.phone,
      ),
    );
  }

  /// Cuanto le falta a esta unidad para llegar, o `null` si no corresponde.
  ///
  /// Solo se pide para el administrador y solo con el viaje ya en curso: uno
  /// programado todavia no tiene desde donde medir, y una unidad sin destino
  /// conocido no admite estimacion.
  Future<Duration?>? _tiempoHastaElDestino(LiveVehicleRecord vehiculo) {
    if (!widget.esAdministrador) return null;
    final origen = vehiculo.currentLocation;
    final serviceId = vehiculo.serviceId;
    if (origen == null || serviceId == null) return null;

    final servicio = widget.viewModel.services
        .where((item) => item.id == serviceId)
        .firstOrNull;
    if (servicio == null || servicio.isTerminal) return null;
    final destinoLat = servicio.destinationLatitude;
    final destinoLng = servicio.destinationLongitude;
    if (destinoLat == null || destinoLng == null) return null;

    return const RoadRoutingService().tiempoHastaDestino(
      LatLng(origen.latitude, origen.longitude),
      LatLng(destinoLat, destinoLng),
    );
  }

  String? _marcadorDelConductor(List<MapVehicleVisual> vehicles) {
    final driverId = widget.ubicarDriverId;
    if (driverId == null) return null;
    // En servicio: el marcador lleva el id del vehículo, no el del conductor,
    // así que se busca en las posiciones en vivo cuál le corresponde.
    for (final live in widget.viewModel.liveVehicles) {
      if (live.driverId == driverId && live.currentLocation != null) {
        final id = '${live.vehicleId}:${live.serviceId ?? 'unassigned'}';
        if (vehicles.any((vehicle) => vehicle.id == id)) return id;
      }
    }
    // Sin servicio: marcador de presencia.
    final presencia = 'driver-presence:$driverId';
    if (vehicles.any((vehicle) => vehicle.id == presencia)) return presencia;
    return null;
  }

  final _searchController = SearchController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driverNames = {
      for (final driver in widget.viewModel.drivers) driver.id: driver.fullName,
    };
    final liveByService = <String, LiveVehicleRecord>{
      for (final vehicle in widget.viewModel.liveVehicles)
        if (vehicle.serviceId != null) vehicle.serviceId!: vehicle,
    };
    // En el mapa sólo van los viajes en curso. Los cancelados y finalizados
    // seguían dibujándose como si todavía estuvieran rodando.
    final enRuta = widget.viewModel.services
        .where((service) => service.isDrawableOnMap)
        .toList(growable: false);
    final routes = <RouteVisual>[
      if (!widget.hideRoutes)
        for (var i = 0; i < enRuta.length; i++)
          RouteVisual(
            service: enRuta[i],
            color: _routePalette[i % _routePalette.length],
            highlighted: i == 0,
            actualPoints: [
              for (final point in enRuta[i].actualRoute)
                LatLng(point.latitude, point.longitude),
              for (final point
                  in liveByService[enRuta[i].id]?.actualRoute ??
                      const <LocationPoint>[])
                LatLng(point.latitude, point.longitude),
            ],
          ),
    ];
    final liveVehicleDriverIds = {
      for (final vehicle in widget.viewModel.liveVehicles)
        if (vehicle.currentLocation != null && vehicle.driverId != null)
          vehicle.driverId!,
    };
    final vehicles = <MapVehicleVisual>[
      for (final vehicle in widget.viewModel.liveVehicles)
        if (vehicle.currentLocation != null)
          MapVehicleVisual(
            id: '${vehicle.vehicleId}:${vehicle.serviceId ?? 'unassigned'}',
            routeId: vehicle.serviceId,
            point: LatLng(
              vehicle.currentLocation!.latitude,
              vehicle.currentLocation!.longitude,
            ),
            heading: vehicle.headingDeg ?? 0,
            stale: vehicle.isStale,
            useCarMarker: true,
            label:
                '${vehicle.vehiclePlate} · ${vehicle.driverName ?? 'Sin conductor'} · '
                '${vehicle.serviceCode ?? 'Sin servicio'} · ${vehicle.status}',
          ),
      for (final driver in widget.viewModel.liveDrivers)
        if (driver.hasPosition &&
            !liveVehicleDriverIds.contains(driver.driverId))
          MapVehicleVisual(
            id: 'driver-presence:${driver.driverId}',
            point: LatLng(driver.latitude!, driver.longitude!),
            heading: driver.heading ?? 0,
            stale: driver.stale || !driver.available,
            useCarMarker: true,
            label:
                '${driver.driverName.isEmpty ? driverNames[driver.driverId] ?? 'Conductor' : driver.driverName} · '
                '${driver.available ? 'Disponible' : 'No disponible'}',
          ),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: OrganicRouteMap(
            routes: routes,
            initialZoom: 11.2,
            showEmptyMap: true,
            selectedRouteId: widget.selectedRouteId,
            draftPickup: widget.draftPickup,
            draftDestination: widget.draftDestination,
            onRouteSelected: widget.onRouteSelected,
            vehicles: vehicles,
            onVehicleTap: _mostrarResumenDeUnidad,
            // Centra al conductor que se pidió ubicar.
            followVehicleId: _marcadorDelConductor(vehicles),
            followVehicleCentered: widget.ubicarDriverId != null,
            zoomControlsBottomInset: widget.zoomControlsBottomInset,
          ),
        ),
        if (!widget.hideRoutes)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            left: 16,
            right: 16,
            child: SearchAnchor.bar(
              searchController: _searchController,
              isFullScreen: false,
              viewConstraints: const BoxConstraints(maxHeight: 360),
              shrinkWrap: true,
              barHintText: 'Buscar por contacto, placa o ID',
              viewHintText: 'Contacto, placa o ID de ruta',
              barLeading: const SizedBox.shrink(),
              barTrailing: const [
                Icon(Icons.search_rounded, color: appBlack),
                SizedBox(width: 4),
              ],
              barElevation: const WidgetStatePropertyAll(0),
              barBackgroundColor: const WidgetStatePropertyAll(appWhite),
              barTextStyle: const WidgetStatePropertyAll(
                TextStyle(color: appBlack, fontWeight: FontWeight.w700),
              ),
              barHintStyle: const WidgetStatePropertyAll(
                TextStyle(color: Color(0xFF666666)),
              ),
              barSide: const WidgetStatePropertyAll(
                BorderSide(color: appBlack, width: 0.5),
              ),
              barShape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              viewBackgroundColor: appWhite,
              viewElevation: 0,
              viewSide: const BorderSide(color: appBlack, width: 0.5),
              viewHeaderTextStyle: const TextStyle(
                color: appBlack,
                fontWeight: FontWeight.w700,
              ),
              viewHeaderHintStyle: const TextStyle(color: Color(0xFF666666)),
              dividerColor: const Color(0x33000000),
              viewShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              suggestionsBuilder: (context, controller) {
                final query = controller.text.trim().toLowerCase();
                final matches = widget.viewModel.services.where((service) {
                  return service.id.toLowerCase().contains(query) ||
                      service.code.toLowerCase().contains(query) ||
                      (service.driverName ?? '').toLowerCase().contains(
                        query,
                      ) ||
                      (service.vehiclePlate ?? '').toLowerCase().contains(
                        query,
                      );
                });
                return matches.map((service) {
                  final routeIndex = widget.viewModel.services.indexWhere(
                    (route) => route.id == service.id,
                  );
                  final routeColor =
                      _routePalette[routeIndex % _routePalette.length];
                  return ListTile(
                    leading: Icon(Icons.route_rounded, color: routeColor),
                    title: Text(
                      service.code,
                      style: const TextStyle(color: appBlack),
                    ),
                    subtitle: Text(
                      '${service.driverName ?? 'Sin contacto'} · '
                      '${service.vehiclePlate ?? 'Sin placa'}',
                      style: const TextStyle(color: Color(0xFF666666)),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: appBlack,
                    ),
                    onTap: () {
                      _searchController.closeView(service.code);
                      widget.onRouteSelected(service);
                    },
                  );
                });
              },
            ),
          ),
        if (!widget.hideRoutes &&
            (widget.viewModel.liveDriversError != null ||
                widget.viewModel.liveVehiclesError != null))
          Positioned(
            top: MediaQuery.paddingOf(context).top + 84,
            left: 16,
            right: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE9B949),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Text(
                  widget.viewModel.liveDriversError ??
                      widget.viewModel.liveVehiclesError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appBlack,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RouteDetailsSheet extends StatefulWidget {
  const _RouteDetailsSheet({
    required this.service,
    required this.routeColor,
    required this.liveVehicle,
  });

  final TransportService service;
  final Color routeColor;
  final LiveVehicleRecord? liveVehicle;

  @override
  State<_RouteDetailsSheet> createState() => _RouteDetailsSheetState();
}

class _RouteDetailsSheetState extends State<_RouteDetailsSheet> {
  bool _showMore = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final routeColor = widget.routeColor;
    final liveVehicle = widget.liveVehicle;
    final sheetTheme = buildAppSheetTheme();
    return Theme(
      data: sheetTheme,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFA6A6A6),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF666666),
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    service.driverName ?? 'Sin driver asignado',
                              ),
                              TextSpan(
                                text:
                                    ' — ${service.vehiclePlate ?? 'Sin unidad'}',
                                style: const TextStyle(
                                  color: Color(0xFF666666),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sheetTheme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${service.code} · '
                          '${statusLabel(service.currentStatus)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF666666),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE1E1E1)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, color: routeColor, size: 20),
                  const SizedBox(width: 9),
                  Text(
                    formatDateTime(service.scheduledAt, includeYear: true),
                    style: const TextStyle(
                      color: appBlack,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _RouteStop(
                icon: Icons.trip_origin_rounded,
                color: routeColor,
                label: 'Origen',
                value: service.pickupAddress,
              ),
              const Padding(
                padding: EdgeInsets.only(left: 9),
                child: SizedBox(
                  height: 18,
                  child: VerticalDivider(
                    width: 2,
                    thickness: 2,
                    color: Color(0xFFBDBDBD),
                  ),
                ),
              ),
              _RouteStop(
                icon: Icons.flag_rounded,
                color: routeColor,
                label: 'Destino',
                value: service.destinationAddress,
              ),
              if (service.notes != null &&
                  service.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE1E1E1)),
                const SizedBox(height: 6),
                _RouteStop(
                  icon: Icons.notes_rounded,
                  color: routeColor,
                  label: 'Notas',
                  value: service.notes!,
                ),
              ],
              if (liveVehicle != null) ...[
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE1E1E1)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => setState(() => _showMore = !_showMore),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _showMore
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: routeColor,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Más info',
                          style: TextStyle(
                            color: appBlack,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showMore) ...[
                  const SizedBox(height: 4),
                  _LiveRouteData(
                    label: 'Hora de inicio',
                    value: _formatOptionalDate(liveVehicle.startedAt),
                  ),
                  _LiveRouteData(
                    label: 'Orientación',
                    value: liveVehicle.headingDeg == null
                        ? 'No disponible'
                        : '${liveVehicle.headingDeg!.round()}°',
                  ),
                  if (liveVehicle.isStale)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Ubicación temporalmente desactualizada',
                        style: TextStyle(
                          color: Color(0xFF7A4D00),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveRouteData extends StatelessWidget {
  const _LiveRouteData({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF666666)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: appBlack,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteStop extends StatelessWidget {
  const _RouteStop({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: appBlack,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatOptionalDate(DateTime? value) =>
    value == null ? 'No disponible' : formatDateTime(value, includeYear: true);

class _CreateRouteSheet extends StatefulWidget {
  const _CreateRouteSheet({
    required this.viewModel,
    required this.onPickupPointChanged,
    required this.onDestinationPointChanged,
  });

  final AdminViewModel viewModel;
  final ValueChanged<LatLng?> onPickupPointChanged;
  final ValueChanged<LatLng?> onDestinationPointChanged;

  @override
  State<_CreateRouteSheet> createState() => _CreateRouteSheetState();
}

class _CreateRouteSheetState extends State<_CreateRouteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pickup = TextEditingController();
  final _destination = TextEditingController();
  String? _driverId;
  String? _vehicleId;
  DateTime _scheduledAt = DateTime.now().add(const Duration(minutes: 30));
  bool _scheduleInvalid = false;
  bool _submitting = false;
  bool _completed = false;

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drivers = widget.viewModel.drivers;
    final vehicles = widget.viewModel.vehicles;
    _driverId ??= drivers.isEmpty ? null : drivers.first.id;
    _vehicleId ??= vehicles.isEmpty ? null : vehicles.first.id;
    final sheetTheme = buildAppSheetTheme();

    return Theme(
      data: sheetTheme,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _completed
            ? const SizedBox(
                key: ValueKey('route-created'),
                height: 320,
                child: _SheetConfirmation(
                  title: 'Ruta creada',
                  subtitle: 'Ya está asignada y visible en el mapa.',
                ),
              )
            : SizedBox.expand(
                key: const ValueKey('route-form'),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      24 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: appLime,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.add_road_rounded,
                                  color: appBlack,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Crear ruta',
                                      style: sheetTheme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    const Text(
                                      'La ruta seguirá calles y avenidas reales.',
                                      style: TextStyle(
                                        color: Color(0xFF666666),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          AddressAutocompleteField(
                            controller: _pickup,
                            label: 'Origen',
                            icon: Icons.trip_origin_rounded,
                            validator: _validateAddress,
                            onPointChanged: widget.onPickupPointChanged,
                          ),
                          const SizedBox(height: 14),
                          AddressAutocompleteField(
                            controller: _destination,
                            label: 'Destino',
                            icon: Icons.flag_rounded,
                            validator: _validateAddress,
                            onPointChanged: widget.onDestinationPointChanged,
                          ),
                          const SizedBox(height: 14),
                          InkWell(
                            onTap: _submitting ? null : _pickSchedule,
                            borderRadius: BorderRadius.circular(18),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Fecha y horario de salida',
                                prefixIcon: const Icon(Icons.schedule_rounded),
                                errorText: _scheduleInvalid
                                    ? 'El horario debe estar en el futuro.'
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    formatDateTime(
                                      _scheduledAt,
                                      includeYear: true,
                                    ),
                                    style: const TextStyle(
                                      color: appBlack,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.edit_calendar_rounded),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _driverId,
                            isExpanded: true,
                            dropdownColor: appWhite,
                            decoration: const InputDecoration(
                              labelText: 'Driver invitado/asignado',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                            items: [
                              for (final driver in drivers)
                                DropdownMenuItem(
                                  value: driver.id,
                                  child: Text(
                                    driver.fullName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: appBlack),
                                  ),
                                ),
                            ],
                            onChanged: _submitting
                                ? null
                                : (value) => setState(() => _driverId = value),
                            validator: (value) =>
                                value == null ? 'Selecciona un driver.' : null,
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _vehicleId,
                            isExpanded: true,
                            dropdownColor: appWhite,
                            decoration: const InputDecoration(
                              labelText: 'Unidad',
                              prefixIcon: Icon(Icons.local_shipping_rounded),
                            ),
                            items: [
                              for (final vehicle in vehicles)
                                DropdownMenuItem(
                                  value: vehicle.id,
                                  child: Text(
                                    '${vehicle.plate} · '
                                    '${vehicle.model ?? 'Unidad'}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: appBlack),
                                  ),
                                ),
                            ],
                            onChanged: _submitting
                                ? null
                                : (value) => setState(() => _vehicleId = value),
                            validator: (value) =>
                                value == null ? 'Selecciona una unidad.' : null,
                          ),
                          if (widget.viewModel.errorMessage != null) ...[
                            const SizedBox(height: 14),
                            _InlineError(
                              message: widget.viewModel.errorMessage!,
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _submitting ? null : _create,
                            child: _submitting
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: appBlack,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Calculando ruta…'),
                                    ],
                                  )
                                : const Text('Crear y asignar ruta'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _create() async {
    final scheduleInvalid = !_scheduledAt.isAfter(DateTime.now());
    setState(() => _scheduleInvalid = scheduleInvalid);
    if (!(_formKey.currentState?.validate() ?? false) || scheduleInvalid) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final created = await widget.viewModel.createRoute(
      pickupAddress: _pickup.text.trim(),
      destinationAddress: _destination.text.trim(),
      driverId: _driverId!,
      vehicleId: _vehicleId!,
      scheduledAt: _scheduledAt,
    );
    if (!mounted) return;
    if (!created) {
      setState(() => _submitting = false);
      return;
    }

    setState(() => _completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _scheduleInvalid = false;
    });
  }

  String? _validateAddress(String? value) {
    if (value == null || value.trim().length < 6) {
      return 'Escribe una dirección completa.';
    }
    return null;
  }
}

class _AssignServiceSheet extends StatefulWidget {
  const _AssignServiceSheet({required this.service, required this.viewModel});

  final TransportService service;
  final AdminViewModel viewModel;

  @override
  State<_AssignServiceSheet> createState() => _AssignServiceSheetState();
}

class _AssignServiceSheetState extends State<_AssignServiceSheet> {
  String? _driverId;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final drivers = widget.viewModel.drivers;
    final reservation = widget.viewModel.reservationForService(
      widget.service.id,
    );
    _driverId ??= reservation?.driverId;
    DriverRecord? selectedDriver;
    for (final driver in drivers) {
      if (driver.id == _driverId) {
        selectedDriver = driver;
        break;
      }
    }
    final reservingDriverId = widget.viewModel.reservingDriverId;
    final busy = _submitting || reservingDriverId != null;
    final sheetTheme = buildAppSheetTheme();

    return Theme(
      data: sheetTheme,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: appLime,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: appBlack,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Asignar servicio',
                          style: sheetTheme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${widget.service.code} · '
                          '${widget.service.destinationAddress}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF666666)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (widget.viewModel.loadingAssignmentData)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: appBlack),
                  ),
                )
              else if (drivers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'El servidor no devolvió conductores para esta solicitud.',
                    style: TextStyle(
                      color: Color(0xFF444444),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else ...[
                const Text(
                  'Conductores',
                  style: TextStyle(
                    color: appBlack,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'La disponibilidad y la reserva provienen del servidor.',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 12),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: drivers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final driver = drivers[index];
                      final selected = reservation?.driverId == driver.id;
                      final canReserve =
                          driver.isAvailableForReservation &&
                          reservation == null &&
                          !busy;
                      final reserving = reservingDriverId == driver.id;
                      return Semantics(
                        button: canReserve,
                        enabled: canReserve,
                        selected: selected,
                        label:
                            '${driver.fullName}. ${driver.availabilityLabel}. '
                            '${driver.vehicleModel ?? 'Vehículo sin modelo'}, '
                            '${driver.vehiclePlate ?? 'sin placa'}.',
                        child: Material(
                          color: selected
                              ? const Color(0xFFEFF6DD)
                              : const Color(0xFFF4F4F1),
                          borderRadius: BorderRadius.circular(18),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: canReserve ? () => _reserve(driver) : null,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? appLime
                                          : const Color(0xFFE3E3DE),
                                      shape: BoxShape.circle,
                                    ),
                                    child: reserving
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: appBlack,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.person_rounded,
                                            color: appBlack,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          driver.fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: appBlack,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Text(
                                          [
                                                    driver.vehicleModel,
                                                    driver.vehiclePlate,
                                                  ]
                                                  .whereType<String>()
                                                  .join(' · ')
                                                  .isEmpty
                                              ? 'Vehículo no informado'
                                              : [
                                                  driver.vehicleModel,
                                                  driver.vehiclePlate,
                                                ].whereType<String>().join(
                                                  ' · ',
                                                ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF666666),
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (driver.reservationOwner != null)
                                          Text(
                                            'Reserva: ${driver.reservationOwner}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF666666),
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _DriverAvailabilityBadge(driver: driver),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (reservation != null && selectedDriver != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6DD),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB8CE70)),
                    ),
                    child: Text(
                      'RESERVADO · ${selectedDriver.fullName}\n'
                      '${selectedDriver.vehicleModel ?? 'Vehículo'} · '
                      '${selectedDriver.vehiclePlate ?? 'Sin placa'}',
                      style: const TextStyle(
                        color: appBlack,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
                if (widget.viewModel.errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _InlineError(message: widget.viewModel.errorMessage!),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed:
                      !busy &&
                          reservation?.confirmed == true &&
                          selectedDriver?.vehicleId != null
                      ? _assign
                      : null,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: appBlack,
                          ),
                        )
                      : const Text('Confirmar asignación'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reserve(DriverRecord driver) async {
    final reserved = await widget.viewModel.reserveDriverForService(
      serviceId: widget.service.id,
      driverId: driver.id,
    );
    if (!mounted || !reserved) return;
    setState(() => _driverId = driver.id);
  }

  Future<void> _assign() async {
    final driverId = _driverId;
    if (driverId == null) return;
    setState(() => _submitting = true);
    final assigned = await widget.viewModel.assignService(
      serviceId: widget.service.id,
      driverId: driverId,
    );
    if (!mounted) return;
    if (!assigned) {
      setState(() => _submitting = false);
      return;
    }
    Navigator.pop(context, true);
  }
}

class _DriverAvailabilityBadge extends StatelessWidget {
  const _DriverAvailabilityBadge({required this.driver});

  final DriverRecord driver;

  @override
  Widget build(BuildContext context) {
    final available = driver.normalizedAvailabilityStatus == 'DISPONIBLE';
    final reserved = driver.normalizedAvailabilityStatus == 'RESERVADO';
    return Container(
      constraints: const BoxConstraints(maxWidth: 94),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: available
            ? appLime
            : reserved
            ? const Color(0xFFFFD166)
            : const Color(0xFFD8D8D3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        driver.availabilityLabel,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: appBlack,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SheetConfirmation extends StatelessWidget {
  const _SheetConfirmation({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: appLime,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: appWhite, size: 52),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }
}

class _InviteDriverSheet extends StatefulWidget {
  const _InviteDriverSheet({required this.viewModel});

  final AdminViewModel viewModel;

  @override
  State<_InviteDriverSheet> createState() => _InviteDriverSheetState();
}

class _InviteDriverSheetState extends State<_InviteDriverSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  final _vehiclePlate = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _seatCount = TextEditingController();
  String? _vehicleType;
  bool _submitting = false;
  bool _completed = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _document.dispose();
    _phone.dispose();
    _vehiclePlate.dispose();
    _vehicleModel.dispose();
    _seatCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheetTheme = buildAppSheetTheme();
    return Theme(
      data: sheetTheme,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _completed
            ? const SizedBox(
                key: ValueKey('invitation-sent'),
                height: 300,
                child: _SheetConfirmation(
                  title: 'Driver creado',
                  subtitle:
                      'Sus datos y vehículo quedaron registrados. La invitación fue enviada.',
                ),
              )
            : SafeArea(
                key: const ValueKey('invitation-form'),
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    20 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: appLime,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Crear driver',
                                    style: sheetTheme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const Text(
                                    'Registra al conductor, su acceso y vehículo.',
                                    style: TextStyle(color: Color(0xFF666666)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar',
                              onPressed: _submitting
                                  ? null
                                  : () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Datos del driver',
                          style: TextStyle(
                            color: appBlack,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Correo del driver',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Escribe un correo válido.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Nombre visible',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 2
                              ? 'Escribe el nombre del driver.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _document,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Documento de identidad',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 6
                              ? 'Escribe un documento válido.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 7
                              ? 'Escribe un teléfono válido.'
                              : null,
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'Vehículo',
                          style: TextStyle(
                            color: appBlack,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _vehiclePlate,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Placa',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 5
                              ? 'Escribe una placa válida.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _vehicleModel,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Marca y modelo',
                            prefixIcon: Icon(Icons.directions_car_outlined),
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 2
                              ? 'Escribe la marca y modelo.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _vehicleType,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de vehículo',
                            prefixIcon: Icon(Icons.airport_shuttle_rounded),
                          ),
                          items: [
                            for (final type in _vehicleTypes)
                              DropdownMenuItem(
                                value: type.value,
                                child: Text(
                                  '${type.label} (mín. ${type.minSeats})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _vehicleType = value;
                              final minSeats = _minSeatsFor(value);
                              final current = int.tryParse(_seatCount.text);
                              if (current == null || current < minSeats) {
                                _seatCount.text = '$minSeats';
                              }
                            });
                          },
                          validator: (value) => value == null
                              ? 'Selecciona el tipo de vehículo.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _seatCount,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Número de asientos',
                            prefixIcon: Icon(Icons.airline_seat_recline_extra),
                          ),
                          validator: (value) {
                            final seats = int.tryParse(value?.trim() ?? '');
                            if (seats == null ||
                                seats < _minSeatsFor(_vehicleType)) {
                              return 'Mínimo ${_minSeatsFor(_vehicleType)} asientos '
                                  'para el tipo seleccionado.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F4F1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.key_rounded,
                                color: Color(0xFF666666),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'El driver ingresa con su correo y su '
                                  'documento de identidad como contraseña.',
                                  style: TextStyle(
                                    color: Color(0xFF444444),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.viewModel.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          _InlineError(message: widget.viewModel.errorMessage!),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _submitting ? null : _invite,
                          child: _submitting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: appBlack,
                                  ),
                                )
                              : const Text('Crear'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _invite() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final invited = await widget.viewModel.inviteDriver(
      email: _email.text.trim(),
      driverName: _name.text.trim(),
      documentNumber: _document.text.trim(),
      phone: _phone.text.trim(),
      vehiclePlate: _vehiclePlate.text.trim().toUpperCase(),
      vehicleModel: _vehicleModel.text.trim(),
      vehicleType: _vehicleType!,
      seatCount: int.parse(_seatCount.text.trim()),
    );
    if (!mounted) return;
    if (!invited) {
      setState(() => _submitting = false);
      return;
    }

    setState(() => _completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (mounted) Navigator.pop(context, true);
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: appBlack),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _friendlyAdminError(message),
            style: const TextStyle(
              color: Color(0xFF444444),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

String _friendlyAdminError(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('request body is invalid')) {
    return 'Revisa los datos ingresados e intenta nuevamente.';
  }
  if (normalized.contains('socketexception') ||
      normalized.contains('connection') ||
      normalized.contains('timed out')) {
    return 'No pudimos conectarnos. Revisa tu conexión e intenta nuevamente.';
  }
  return message.replaceFirst('Exception: ', '');
}

final _adminActionButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: appWhite,
  side: const BorderSide(color: appWhite, width: 1.4),
  minimumSize: const Size.fromHeight(48),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  textStyle: const TextStyle(fontWeight: FontWeight.w800),
);
