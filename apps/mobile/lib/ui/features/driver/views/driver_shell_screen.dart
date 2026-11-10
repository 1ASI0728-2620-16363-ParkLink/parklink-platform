import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../domain/models/in_app_notification.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../domain/models/transport_service.dart';
import '../../../core/app_bottom_nav.dart';
import '../../../core/app_bottom_sheet.dart';
import '../../../core/app_emergency_sheet.dart';
import '../../../core/app_scope.dart';
import '../../../core/app_success_overlay.dart';
import '../../../core/app_theme.dart';
import '../../../core/map_theme.dart';
import '../../../core/date_formats.dart';
import '../../../core/organic_route_map.dart';
import '../../../core/status_styles.dart';
import '../../services/view_models/service_list_view_model.dart';
import '../../services/views/service_detail_screen.dart';

class DriverShellScreen extends StatefulWidget {
  const DriverShellScreen({this.onLoggedOut, super.key});

  final VoidCallback? onLoggedOut;

  @override
  State<DriverShellScreen> createState() => _DriverShellScreenState();
}

class _DriverShellScreenState extends State<DriverShellScreen>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;
  bool _sheetOpen = false;
  bool _detailCollapsed = false;
  String? _selectedServiceId;
  LatLng? _fallbackLocation;
  PersistentBottomSheetController? _detailController;
  late final ServiceListViewModel _viewModel;
  Timer? _notificationTimer;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scope = AppScope.of(context, listen: false);
    _viewModel = ServiceListViewModel(
      serviceRepository: scope.serviceRepository,
      eventRepository: scope.eventRepository,
      authRepository: scope.authRepository,
      syncCoordinator: scope.syncCoordinator,
      backgroundTrackingService: scope.backgroundTrackingService,
      trackingRepository: scope.trackingRepository,
      notificationRepository: scope.notificationRepository,
      driverPresenceRepository: scope.driverPresenceRepository,
      locationService: scope.locationService,
      roadRoutingService: scope.roadRoutingService,
    );
    _load();
    _startNotificationPolling();
    _loadFallbackLocation(scope);
  }

  Future<void> _loadFallbackLocation(AppScope scope) async {
    try {
      final point = await scope.locationService.currentLocation();
      if (mounted) {
        setState(() {
          _fallbackLocation = LatLng(point.latitude, point.longitude);
        });
      }
    } catch (_) {
      // La ubicación inicial mejora el mapa, pero no debe cerrar la app si el
      // permiso está bloqueado, el GPS está apagado o el proveedor tarda.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTimer?.cancel();
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
          return IndexedStack(
            index: _index,
            children: [
              _DriverMapTab(
                viewModel: _viewModel,
                selectedServiceId: _selectedServiceId,
                detailCollapsed: _detailCollapsed,
                fallbackLocation: _fallbackLocation,
                onOpen: _openService,
                onOpenNotifications: _openNotifications,
              ),
              _DriverProfileTab(
                viewModel: _viewModel,
                onSettings: _openSettings,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _sheetOpen
          ? null
          : AppBottomNav(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: 'Planificada',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Perfil',
                ),
              ],
              trailingActions: [
                SizedBox.square(
                  dimension: 68,
                  child: FloatingActionButton(
                    heroTag: 'driver-services',
                    tooltip: 'Servicios',
                    onPressed: _openServices,
                    backgroundColor: appWhite,
                    foregroundColor: appBlack,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: const BorderSide(color: Color(0xFFD8D8D8)),
                    ),
                    child: const Icon(Icons.list_alt_rounded, size: 34),
                  ),
                ),
                SizedBox.square(
                  dimension: 68,
                  child: FloatingActionButton(
                    heroTag: 'driver-emergency',
                    tooltip: 'Emergencia',
                    onPressed: _viewModel.emergencySending
                        ? null
                        : _confirmEmergency,
                    backgroundColor: appEmergency,
                    foregroundColor: appWhite,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: _viewModel.emergencySending
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: appWhite,
                            ),
                          )
                        : const Icon(Icons.sos_rounded, size: 34),
                  ),
                ),
              ],
            ),
    );
  }

  /// Confirmación de servicio iniciado o terminado: fondo oscuro difuminado
  /// con un check, igual que al crear un servicio.
  ///
  /// Se cierra sola: el conductor está al volante y no tiene por qué tocar nada
  /// más para volver al mapa.
  void _mostrarConfirmacion(String titulo) {
    if (!mounted) return;
    unawaited(showAppSuccessOverlay(context, title: titulo));
  }

  Future<void> _load() async {
    await Future.wait([_viewModel.load(), _viewModel.loadNotifications()]);
    if (!mounted || _sheetOpen) return;
    for (final service in _viewModel.services) {
      if (service.allowedActions.any(
        (action) => action != ServiceAction.summary,
      )) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_sheetOpen) _openService(service);
        });
        break;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      _startNotificationPolling();
      unawaited(_viewModel.loadNotifications());
      unawaited(_viewModel.recoverAfterResume());
    } else {
      _notificationTimer?.cancel();
      _notificationTimer = null;
    }
  }

  void _startNotificationPolling() {
    if (!_appActive || _notificationTimer != null) return;
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(_viewModel.loadNotifications()),
    );
  }

  Future<void> _openNotifications() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    final serviceId = await showAppBottomSheet<String>(
      context: context,
      builder: (_) => _NotificationsSheet(viewModel: _viewModel),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (serviceId == null) {
      final error = _viewModel.notificationError;
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    await _viewModel.load();
    if (!mounted) return;
    final matches = _viewModel.services.where(
      (service) => service.id == serviceId,
    );
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El servicio ya no está disponible.')),
      );
      return;
    }
    await _openService(matches.first);
  }

  Future<void> _openServices() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    final service = await showAppBottomSheet<TransportService>(
      context: context,
      builder: (_) => _DriverServicesSheet(viewModel: _viewModel),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    final dedicatedFeedback =
        _viewModel.dedicatedActionError ?? _viewModel.dedicatedActionMessage;
    if (dedicatedFeedback != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dedicatedFeedback)));
      _viewModel.clearDedicatedActionFeedback();
    }
    if (service != null) await _openService(service);
  }

  Future<void> _openService(TransportService service) async {
    if (_sheetOpen) return;
    setState(() {
      _index = 0;
      _sheetOpen = true;
      _detailCollapsed = false;
      _selectedServiceId = service.id;
    });

    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (_) => Theme(
        data: buildAppSheetTheme(),
        child: ServiceDetailSheet(
          serviceId: service.id,
          dedicatedDriver: _viewModel.isDedicatedDriver,
          onClose: _closeDetail,
          onRouteStarted: () {
            setState(() {});
            _mostrarConfirmacion('Servicio iniciado');
          },
          onRouteStopped: () {
            _closeDetail();
            _mostrarConfirmacion('Servicio finalizado');
          },
          onCollapsedChanged: (collapsed) {
            if (mounted) setState(() => _detailCollapsed = collapsed);
          },
        ),
      ),
      backgroundColor: appWhite,
      elevation: 0,
      enableDrag: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      clipBehavior: Clip.antiAlias,
    );
    _detailController = controller;
    await controller.closed;
    _detailController = null;
    if (!mounted) return;
    setState(() {
      _sheetOpen = false;
      _detailCollapsed = false;
      _selectedServiceId = null;
    });
    await _viewModel.load();
  }

  void _closeDetail() => _detailController?.close();

  Future<void> _openSettings() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) =>
          _DriverSettingsSheet(viewModel: _viewModel, onLogout: _logout),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  Future<void> _confirmEmergency() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => AppEmergencySheet(
        onSend: _viewModel.sendEmergency,
        errorMessage: () => _viewModel.emergencyMessage,
      ),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  Future<void> _logout() async {
    await _viewModel.logout();
    if (mounted) widget.onLoggedOut?.call();
  }
}

class _DriverMapTab extends StatefulWidget {
  const _DriverMapTab({
    required this.viewModel,
    required this.selectedServiceId,
    required this.detailCollapsed,
    required this.fallbackLocation,
    required this.onOpen,
    required this.onOpenNotifications,
  });

  final ServiceListViewModel viewModel;
  final String? selectedServiceId;
  final bool detailCollapsed;
  final LatLng? fallbackLocation;
  final Future<void> Function(TransportService) onOpen;
  final VoidCallback onOpenNotifications;

  @override
  State<_DriverMapTab> createState() => _DriverMapTabState();
}

class _DriverMapTabState extends State<_DriverMapTab> {
  /// Navegación tipo GPS: el mapa sigue al conductor y gira para que el camino
  /// quede siempre recto hacia arriba. Se puede apagar para mirar el mapa con
  /// libertad, y el botón de centrar lo vuelve a encender.
  bool _seguirConductor = true;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final selectedServiceId = widget.selectedServiceId;
    final fallbackLocation = widget.fallbackLocation;
    final onOpen = widget.onOpen;
    final onOpenNotifications = widget.onOpenNotifications;
    final trackingServiceId = viewModel.trackingServiceId;
    final lastLocation = viewModel.driverLocation;
    // Sólo se dibuja la ruta del servicio en curso. Un viaje cancelado o
    // finalizado seguía apareciendo en el mapa del conductor como si todavía
    // tuviera que hacerlo.
    // Cada ruta con su color, para poder distinguirlas cuando hay varias.
    final dibujables = viewModel.services
        .where((service) => service.isDrawableOnMap)
        .toList(growable: false);
    final routes = [
      for (var i = 0; i < dibujables.length; i++)
        RouteVisual(
          service: dibujables[i],
          color: _driverRoutePalette[i % _driverRoutePalette.length],
          highlighted:
              selectedServiceId == null ||
              selectedServiceId == dibujables[i].id,
          actualPoints: trackingServiceId == dibujables[i].id
              ? _routePoints(
                  dibujables[i].actualRoute,
                  viewModel.localTrackingRoute,
                )
              : const [],
        ),
    ];
    final vehicles = <MapVehicleVisual>[
      if (lastLocation != null)
        MapVehicleVisual(
          id: 'driver-current-location',
          routeId: trackingServiceId,
          point: LatLng(lastLocation.latitude, lastLocation.longitude),
          heading: lastLocation.heading ?? 0,
          label: 'Ubicación actual del conductor',
          stale: trackingServiceId != null && !viewModel.isTracking,
        ),
    ];
    return Stack(
      children: [
        OrganicRouteMap(
          routes: routes,
          initialZoom: 11.2,
          selectedRouteId: selectedServiceId,
          onRouteSelected: onOpen,
          vehicles: vehicles,
          followVehicleId: vehicles.isEmpty || !_seguirConductor
              ? null
              : vehicles.first.id,
          followVehicleCentered: _seguirConductor,
          headingUp: _seguirConductor,
          userLocation: lastLocation == null ? fallbackLocation : null,
          showEmptyMap: true,
          zoomControlsBottomInset: 16,
        ),
        // Centrar de nuevo tras haber movido el mapa a mano.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton.filled(
                tooltip: _seguirConductor
                    ? 'Dejar de seguir mi posición'
                    : 'Centrar en mi posición',
                onPressed: () =>
                    setState(() => _seguirConductor = !_seguirConductor),
                style: IconButton.styleFrom(
                  backgroundColor: _seguirConductor ? appLime : appWhite,
                  foregroundColor: _seguirConductor ? appWhite : appLime,
                  minimumSize: const Size.square(52),
                ),
                icon: Icon(
                  _seguirConductor
                      ? Icons.gps_fixed_rounded
                      : Icons.gps_not_fixed_rounded,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topRight,
              child: Badge.count(
                count: viewModel.unreadNotificationCount,
                isLabelVisible: viewModel.unreadNotificationCount > 0,
                child: IconButton.filled(
                  tooltip: 'Notificaciones',
                  onPressed: onOpenNotifications,
                  style: IconButton.styleFrom(
                    backgroundColor: appBlack.withValues(alpha: 0.9),
                    foregroundColor: appWhite,
                    minimumSize: const Size.square(52),
                  ),
                  icon: const Icon(Icons.notifications_outlined),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<LatLng> _routePoints(
    List<LocationPoint> confirmed,
    List<LocationPoint> local,
  ) {
    final seen = <String>{};
    return [
      for (final point in [...confirmed, ...local])
        if (seen.add(
          '${point.capturedAt?.toIso8601String() ?? ''}:'
          '${point.latitude}:${point.longitude}',
        ))
          LatLng(point.latitude, point.longitude),
    ];
  }
}

class _NotificationsSheet extends StatelessWidget {
  const _NotificationsSheet({required this.viewModel});

  final ServiceListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notificaciones',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualizar notificaciones',
                        onPressed: viewModel.loadNotifications,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (viewModel.notificationError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  viewModel.notificationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: viewModel.notifications.isEmpty
                  ? const Center(child: Text('No hay notificaciones.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      itemCount: viewModel.notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _NotificationTile(
                        notification: viewModel.notifications[index],
                        onTap: () async {
                          final serviceId = await viewModel.openNotification(
                            viewModel.notifications[index],
                          );
                          if (context.mounted && serviceId != null) {
                            Navigator.pop(context, serviceId);
                          }
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final InAppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = notification.createdAt == null
        ? null
        : formatDateTime(notification.createdAt!);
    return Material(
      color: notification.read
          ? const Color(0xFFF1F1EE)
          : const Color(0xFFEFF6DD),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                notification.read
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                color: appBlack,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: const TextStyle(
                        color: appBlack,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: const TextStyle(color: Color(0xFF555551)),
                    ),
                    if (date != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        date,
                        style: const TextStyle(
                          color: Color(0xFF777772),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: appBlack),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverServicesSheet extends StatelessWidget {
  const _DriverServicesSheet({required this.viewModel});

  final ServiceListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => PopScope(
        canPop: !viewModel.dedicatedActionBusy,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.64,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Servicios',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: viewModel.dedicatedActionBusy
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (viewModel.canStartDedicatedDuty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      key: const ValueKey('start-dedicated-service'),
                      onPressed: viewModel.dedicatedActionBusy
                          ? null
                          : () => _startDedicated(context),
                      icon: viewModel.dedicatedActionBusy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: appWhite,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        viewModel.dedicatedActionBusy
                            ? 'Obteniendo ubicación…'
                            : 'Iniciar servicio',
                      ),
                    ),
                  ),
                ),
              ],
              if (viewModel.dedicatedActionError != null)
                _DedicatedServiceFeedback(
                  message: viewModel.dedicatedActionError!,
                  isError: true,
                )
              else if (viewModel.dedicatedActionMessage != null)
                _DedicatedServiceFeedback(
                  message: viewModel.dedicatedActionMessage!,
                  isError: false,
                ),
              Expanded(
                child: viewModel.services.isEmpty
                    ? Center(
                        child: Text(
                          viewModel.isDedicatedDriver
                              ? 'Inicia tu servicio dedicado cuando estés listo.'
                              : 'No hay servicios asignados.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: viewModel.services.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final service = viewModel.services[index];
                          return _ServiceTile(
                            service: service,
                            onTap: viewModel.dedicatedActionBusy
                                ? null
                                : () => Navigator.pop(context, service),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startDedicated(BuildContext context) async {
    final service = await viewModel.startDedicatedDuty();
    if (context.mounted && service != null) Navigator.pop(context, service);
  }
}

class _DedicatedServiceFeedback extends StatelessWidget {
  const _DedicatedServiceFeedback({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: TextStyle(
            color: isError ? const Color(0xFF9B1C1C) : const Color(0xFF3E5900),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap});

  final TransportService service;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = statusLabel(service.currentStatus);

    return Material(
      color: const Color(0xFFF1F1EE),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: appBlack,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.route_rounded, color: appWhite),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.code,
                      style: const TextStyle(
                        color: appBlack,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      service.isDedicated
                          ? service.hasActiveDedicatedDuty
                                ? 'Servicio dedicado en curso · ${service.dedicatedStops.length} parada(s)'
                                : 'Servicio dedicado'
                          : service.destinationAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF656561)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                state,
                style: const TextStyle(
                  color: appBlack,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: appBlack),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverProfileTab extends StatelessWidget {
  const _DriverProfileTab({required this.viewModel, required this.onSettings});

  final ServiceListViewModel viewModel;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    final user = viewModel.currentUser;
    final profile = viewModel.driverProfile;
    final service = viewModel.services.isEmpty
        ? null
        : viewModel.services.first;
    final name = profile?.fullName ?? user?.fullName ?? 'Conductor';
    final plate =
        profile?.vehiclePlate ?? service?.vehiclePlate ?? 'SIN UNIDAD';
    final model =
        profile?.vehicleModel ?? service?.vehicleModel ?? 'No registrado';
    final completedTrips = viewModel.services
        .where(
          (service) => const {
            'FINALIZADO',
            'COMPLETADO',
            'COMPLETED',
            'FINISHED',
          }.contains(service.normalizedStatus),
        )
        .length;
    final pendingServices = viewModel.services
        .where((service) => !service.isTerminal)
        .length;
    final driverActive = profile?.status.trim().toUpperCase() == 'ACTIVE';

    return ColoredBox(
      color: appBlack,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 124),
        children: [
          SizedBox(
            height: 330,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  bottom: 129,
                  child: Image.asset(
                    'assets/images/profile_map.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 10,
                  left: 16,
                  child: IconButton(
                    tooltip: 'Ajustes',
                    onPressed: onSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: appWhite,
                      foregroundColor: appLime,
                      minimumSize: const Size.square(50),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 30),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 18,
                  right: 22,
                  child: Image.asset(
                    'assets/images/logo_centinela.png',
                    width: 34,
                    height: 34,
                  ),
                ),
                Positioned(
                  top: 92,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _DriverAvatar(
                      avatarUrl: profile?.avatarUrl,
                      name: name,
                    ),
                  ),
                ),
                Positioned(
                  top: 274,
                  left: 20,
                  right: 20,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                Positioned(
                  top: 302,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'CONDUCTOR',
                        style: TextStyle(
                          color: appLime,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          VehicleProfileCard(
            plate: plate,
            model: model,
            vehicleType: profile?.vehicleType,
            seatCount: profile?.seatCount,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 36),
            child: _DriverInfoCard(
              documentNumber: profile?.documentNumber ?? 'No registrado',
              phone: profile?.phone ?? 'Teléfono no registrado',
              email: user?.email ?? 'Correo no disponible',
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 30),
            child: _DriverStats(
              completedTrips: completedTrips,
              pendingServices: pendingServices,
              active: driverActive,
            ),
          ),
          if (viewModel.warningMessage != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 52),
              child: Text(
                viewModel.warningMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.avatarUrl, required this.name});

  final String? avatarUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final fallback = ColoredBox(
      color: const Color(0xFFE7E7E3),
      child: Center(
        child: Text(
          initials.isEmpty ? 'C' : initials,
          style: const TextStyle(
            color: appBlack,
            fontSize: 44,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    return Container(
      width: 172,
      height: 172,
      padding: const EdgeInsets.all(5),
      decoration: const BoxDecoration(color: appWhite, shape: BoxShape.circle),
      child: ClipOval(
        child: avatarUrl == null || avatarUrl!.trim().isEmpty
            ? fallback
            : Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class VehicleProfileCard extends StatelessWidget {
  const VehicleProfileCard({
    required this.plate,
    required this.model,
    required this.vehicleType,
    required this.seatCount,
    super.key,
  });

  final String plate;
  final String model;
  final String? vehicleType;
  final int? seatCount;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight =
        (260 +
                (screenWidth < 360 ? 20 : 0) +
                ((textScale - 1).clamp(0, 1) * 220))
            .toDouble();
    final normalizedType = vehicleType?.trim().toUpperCase();
    final typeLabel = switch (normalizedType) {
      'AUTO_EXECUTIVO' || 'SUV' => 'SUV EJECUTIVO',
      'AUTO_SEDAN' || 'SEDAN' => 'SEDÁN',
      'VAN' => 'VAN',
      'OMNIBUS' || 'ÓMNIBUS' || 'BUS' => 'ÓMNIBUS',
      _ =>
        vehicleType?.trim().isNotEmpty == true
            ? vehicleType!.trim()
            : 'Sin registrar',
    };
    final imageAsset = switch (normalizedType) {
      'AUTO_EXECUTIVO' || 'SUV' => 'assets/images/vehicle_suv.png',
      'VAN' => 'assets/images/vehicle_van.png',
      'OMNIBUS' || 'ÓMNIBUS' || 'BUS' => 'assets/images/vehicle_bus.png',
      _ => 'assets/images/vehicle_top.png',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: SizedBox(
            width: double.infinity,
            height: cardHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 310;
                return Row(
                  children: [
                    Expanded(
                      flex: compact ? 4 : 5,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(29),
                          ),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 14),
                            Text(
                              plate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: appWhite,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child:
                                    imageAsset ==
                                        'assets/images/vehicle_top.png'
                                    ? RotatedBox(
                                        quarterTurns: 1,
                                        child: Image.asset(
                                          imageAsset,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : Image.asset(
                                        imageAsset,
                                        fit: BoxFit.contain,
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Image.asset(
                                  'assets/images/logo_centinela.png',
                                  width: 20,
                                  height: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: compact ? 5 : 4,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 12 : 16,
                          16,
                          compact ? 12 : 14,
                          14,
                        ),
                        decoration: const BoxDecoration(
                          color: appWhite,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(29),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Características',
                              style: TextStyle(
                                color: appBlack,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'MODELO',
                              style: TextStyle(
                                color: Color(0xFF777772),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              model,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: appBlack,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 13),
                            const Text(
                              'TIPO',
                              style: TextStyle(
                                color: Color(0xFF777772),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              typeLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: appBlack,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'CAPACIDAD',
                              style: TextStyle(
                                color: Color(0xFF777772),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              seatCount == null
                                  ? 'Sin registrar'
                                  : '$seatCount pasajeros',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: appBlack,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverInfoCard extends StatelessWidget {
  const _DriverInfoCard({
    required this.documentNumber,
    required this.phone,
    required this.email,
  });

  final String documentNumber;
  final String phone;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: appWhite,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_rounded, color: appBlack, size: 22),
              SizedBox(width: 9),
              Text(
                'DATOS DEL CONDUCTOR',
                style: TextStyle(
                  color: appBlack,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DriverInfoField(label: 'TELÉFONO', value: phone),
              ),
              const SizedBox(
                height: 42,
                child: VerticalDivider(width: 24, color: Color(0xFFD8D8D3)),
              ),
              Expanded(
                child: _DriverInfoField(
                  label: 'DOCUMENTO',
                  value: 'DNI $documentNumber',
                ),
              ),
            ],
          ),
          const Divider(height: 28, color: Color(0xFFD8D8D3)),
          _DriverInfoField(label: 'CORREO', value: email),
        ],
      ),
    );
  }
}

class _DriverInfoField extends StatelessWidget {
  const _DriverInfoField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF777772),
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: appBlack,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DriverStats extends StatelessWidget {
  const _DriverStats({
    required this.completedTrips,
    required this.pendingServices,
    required this.active,
  });

  final int completedTrips;
  final int pendingServices;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DriverStatCircle(value: '$completedTrips', label: 'Viajes'),
        const SizedBox(width: 12),
        _DriverStatCircle(value: '$pendingServices', label: 'Pendientes'),
        const SizedBox(width: 12),
        _DriverStatCircle(
          icon: active ? Icons.check_rounded : Icons.close_rounded,
          label: active ? 'Activo' : 'Fuera de servicio',
          highlighted: active,
        ),
      ],
    );
  }
}

class _DriverStatCircle extends StatelessWidget {
  const _DriverStatCircle({
    this.value,
    this.icon,
    required this.label,
    this.highlighted = false,
  });

  final String? value;
  final IconData? icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final foreground = highlighted ? appBlack : appWhite;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: highlighted ? appLime : const Color(0xFF151515),
              shape: BoxShape.circle,
              border: highlighted
                  ? null
                  : Border.all(color: const Color(0xFF343431)),
            ),
            alignment: Alignment.center,
            child: icon == null
                ? Text(
                    value ?? '—',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Icon(icon, color: foreground, size: 24),
          ),
          const SizedBox(height: 6),
          // En pantallas angostas la etiqueta se encoge hasta entrar en una
          // sola línea, en vez de partirse en dos o cortarse con puntos.
          // "Fuera de servicio" es la que obliga a esto.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: appWhite,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverSettingsSheet extends StatelessWidget {
  const _DriverSettingsSheet({required this.viewModel, required this.onLogout});

  final ServiceListViewModel viewModel;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ajustes',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1EE),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ya no es un interruptor: mientras la sesión esté abierta y
                    // haya permiso de ubicación, el conductor se ve en el mapa
                    // del panel aunque no tenga nada asignado.
                    ListTile(
                      title: const Text(
                        'Visible en el mapa',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(_presenceDescription(viewModel)),
                      leading: Icon(
                        viewModel.presenceAvailable
                            ? Icons.location_on_rounded
                            : Icons.location_off_outlined,
                        color: appBlack,
                      ),
                      trailing: viewModel.presenceUpdating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : null,
                    ),
                    // Cuando el interruptor falla por permisos, avisar no basta:
                    // el permiso bloqueado sólo se devuelve desde Ajustes y no
                    // hay forma de llegar ahí desde la app.
                    if (viewModel.presenceError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: viewModel.openLocationSettings,
                            icon: const Icon(Icons.settings_rounded, size: 18),
                            label: const Text('Abrir ajustes de ubicación'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Sincronización'),
                subtitle: Text(
                  viewModel.pendingCount == 0
                      ? 'Todos los datos están sincronizados.'
                      : '${viewModel.pendingCount} elemento(s) pendientes.',
                ),
                trailing: IconButton(
                  tooltip: 'Sincronizar ahora',
                  onPressed: viewModel.sync,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notificaciones'),
                subtitle: const Text(
                  'Recibirás asignaciones, cambios y alertas importantes.',
                ),
              ),
              ValueListenableBuilder<MapTheme>(
                valueListenable: mapThemeController,
                builder: (context, mapTheme, _) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Tema del mapa'),
                  subtitle: Text('Actualmente: ${mapTheme.label}.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showMapThemePicker(context),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onLogout();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: appBlack,
                    foregroundColor: appWhite,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _presenceDescription(ServiceListViewModel viewModel) {
    final error = viewModel.presenceError;
    if (error != null) return error;
    if (viewModel.presenceUpdating) return 'Actualizando disponibilidad…';
    if (viewModel.presencePausedForRoute) {
      return 'Disponible · ubicación cubierta por la ruta activa.';
    }
    if (viewModel.isSharingPresenceLocation) {
      final updatedAt = viewModel.lastPresenceUpdate;
      return updatedAt == null
          ? 'Esperando la primera ubicación.'
          : 'Última ubicación: ${formatTime(updatedAt, includeSeconds: true)}';
    }
    if (viewModel.presencePausedForRoute) {
      return 'Compartiendo ubicación del servicio en curso.';
    }
    return viewModel.presenceAvailable
        ? 'Tu posición se ve en el mapa del panel.'
        : 'Sin ubicación: revisa el permiso para salir en el mapa.';
  }
}

/// Colores de ruta del conductor: los mismos que usa el panel de administración.
const _driverRoutePalette = [
  appLime,
  Color(0xFF38BDF8),
  Color(0xFFF472B6),
  Color(0xFFFBBF24),
  Color(0xFFA78BFA),
];
