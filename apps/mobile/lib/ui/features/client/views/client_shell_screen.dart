import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/models/transport_service.dart';
import '../../../../data/repositories/notification_repository.dart';
import '../../../core/address_autocomplete_field.dart';
import '../../../core/app_bottom_nav.dart';
import '../../../core/app_bottom_sheet.dart';
import '../../../core/app_emergency_sheet.dart';
import '../../../core/app_scope.dart';
import '../../../core/app_theme.dart';
import '../../../core/map_theme.dart';
import '../../../core/date_formats.dart';
import '../../../core/organic_route_map.dart';
import '../../../core/status_styles.dart';
import '../view_models/client_view_model.dart';

class ClientShellScreen extends StatefulWidget {
  const ClientShellScreen({this.onLoggedOut, super.key});

  final VoidCallback? onLoggedOut;

  @override
  State<ClientShellScreen> createState() => _ClientShellScreenState();
}

class _ClientShellScreenState extends State<ClientShellScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _sheetOpen = false;
  LatLng? _draftPickup;
  LatLng? _draftDestination;
  late final ClientViewModel _viewModel;
  late final NotificationRepository _notificationRepository;
  String? _emergencyError;

  /// Aviso de "tu servicio inició". Se muestra una sola vez, cuando el viaje
  /// pasa a estar en curso: el cliente pidió el servicio y tiene que enterarse
  /// sin depender de que le llegue una notificación al teléfono.
  bool _serviceStartedNotice = false;
  bool _yaAvisadoDelInicio = false;

  void _vigilarInicioDelServicio() {
    final activo = _viewModel.activeRequest;
    if (activo == null || !activo.isUnderway) {
      // Terminado o cancelado: se rearma para el próximo viaje.
      if (activo == null) _yaAvisadoDelInicio = false;
      return;
    }
    if (_yaAvisadoDelInicio) return;
    _yaAvisadoDelInicio = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _serviceStartedNotice = true);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scope = AppScope.of(context, listen: false);
    _notificationRepository = scope.notificationRepository;
    _viewModel = ClientViewModel(
      clientServiceRepository: scope.clientServiceRepository,
      locationService: scope.locationService,
      sessionStore: scope.sessionStore,
    );
    _viewModel.setServerUpdatesEnabled(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final activeRequest = _viewModel.activeRequest;
        final isSearching = activeRequest?.isSearchingForDriver ?? false;
        _vigilarInicioDelServicio();
        return Stack(
          children: [
            Scaffold(
              extendBody: true,
              body: IndexedStack(
                index: _index,
                children: [
                  _ClientMapTab(
                    viewModel: _viewModel,
                    draftPickup: _draftPickup,
                    draftDestination: _draftDestination,
                  ),
                  _ClientProfileTab(
                    viewModel: _viewModel,
                    onSettings: _openSettings,
                  ),
                ],
              ),
              bottomNavigationBar: _sheetOpen
                  ? null
                  : AppBottomNav(
                      selectedIndex: _index,
                      onDestinationSelected: (value) =>
                          setState(() => _index = value),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.map_outlined),
                          selectedIcon: Icon(Icons.map_rounded),
                          label: 'Mapa',
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
                            heroTag: 'client-request',
                            tooltip: _viewModel.hasActiveRequest
                                ? 'Ya tienes una solicitud activa'
                                : 'Solicitar servicio',
                            onPressed: _viewModel.canOpenRequestSheet
                                ? _openRequestSheet
                                : null,
                            backgroundColor: appLime,
                            foregroundColor: appWhite,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Icon(
                              _viewModel.hasActiveRequest
                                  ? Icons.route_rounded
                                  : Icons.add_location_alt_rounded,
                              size: 34,
                            ),
                          ),
                        ),
                        SizedBox.square(
                          dimension: 68,
                          child: FloatingActionButton(
                            heroTag: 'client-emergency',
                            tooltip: 'Emergencia',
                            onPressed: _confirmEmergency,
                            backgroundColor: appEmergency,
                            foregroundColor: appWhite,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(Icons.sos_rounded, size: 34),
                          ),
                        ),
                      ],
                    ),
            ),
            if (isSearching)
              Positioned.fill(
                child: _SearchingForDriverOverlay(
                  replacementSearch: _viewModel.searchingForReplacement,
                ),
              ),
            if (_serviceStartedNotice)
              Positioned.fill(
                child: _ServiceStartedOverlay(
                  driverName: activeRequest?.driverName,
                  onDone: () => setState(() => _serviceStartedNotice = false),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _viewModel.setServerUpdatesEnabled(state == AppLifecycleState.resumed);
  }

  Future<void> _openRequestSheet() async {
    if (_sheetOpen) return;
    if (_viewModel.loadingServices) return;
    if (_viewModel.hasActiveRequest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ya tienes una solicitud activa. Espera a que finalice antes de crear otra.',
          ),
        ),
      );
      return;
    }
    _viewModel.clearSubmissionFeedback();
    setState(() {
      _draftPickup = null;
      _draftDestination = null;
      _sheetOpen = true;
    });
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: appWhite,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => ClientRequestSheet(
        viewModel: _viewModel,
        onPickupPointChanged: (point) {
          if (mounted) setState(() => _draftPickup = point);
        },
        onDestinationPointChanged: (point) {
          if (mounted) setState(() => _draftDestination = point);
        },
      ),
    );
    if (mounted) {
      setState(() {
        _draftPickup = null;
        _draftDestination = null;
        _sheetOpen = false;
      });
      if (submitted == true) unawaited(_viewModel.loadServices());
    }
  }

  Future<void> _logout() async {
    await AppScope.of(context, listen: false).authRepository.logout();
    if (mounted) widget.onLoggedOut?.call();
  }

  Future<void> _openSettings() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => _ClientSettingsSheet(onLogout: _logout),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  Future<void> _confirmEmergency() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => AppEmergencySheet(
        onSend: _sendEmergency,
        errorMessage: () => _emergencyError,
      ),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  Future<bool> _sendEmergency() async {
    _emergencyError = null;
    try {
      await _notificationRepository.sendEmergency(
        serviceId: _viewModel.activeRequest?.id,
      );
      return true;
    } catch (_) {
      _emergencyError =
          'No se pudo enviar la alerta. Intenta nuevamente o llama a emergencias.';
      return false;
    }
  }
}

const _clientPalette = [
  appLime,
  Color(0xFF38BDF8),
  Color(0xFFF472B6),
  Color(0xFFFBBF24),
  Color(0xFFA78BFA),
];

const _searchingMessages = [
  'Estamos procesando tu solicitud…',
  'Buscando un conductor disponible cerca de ti…',
  'Estamos verificando la disponibilidad de nuestros conductores…',
  'Ya casi está listo. Estamos coordinando tu servicio…',
];

class _SearchingForDriverOverlay extends StatefulWidget {
  const _SearchingForDriverOverlay({required this.replacementSearch});

  final bool replacementSearch;

  @override
  State<_SearchingForDriverOverlay> createState() =>
      _SearchingForDriverOverlayState();
}

class _SearchingForDriverOverlayState extends State<_SearchingForDriverOverlay>
    with WidgetsBindingObserver {
  Timer? _messageTimer;
  int _messageIndex = 0;

  String get _message {
    if (widget.replacementSearch && _messageIndex == 0) {
      return 'Estamos buscando otro conductor disponible para atenderte.';
    }
    final offset = widget.replacementSearch ? _messageIndex - 1 : _messageIndex;
    return _searchingMessages[offset % _searchingMessages.length];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startMessageTimer();
  }

  void _startMessageTimer() {
    if (_messageTimer != null) return;
    _messageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _messageIndex++);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startMessageTimer();
    } else {
      _messageTimer?.cancel();
      _messageTimer = null;
    }
  }

  @override
  void didUpdateWidget(covariant _SearchingForDriverOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replacementSearch != widget.replacementSearch) {
      _messageIndex = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return BlockSemantics(
      child: Stack(
        children: [
          const ModalBarrier(
            dismissible: false,
            color: Color(0xD9000000),
            semanticsLabel: 'Buscando conductor. Espera un momento.',
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  scopesRoute: true,
                  label: _message,
                  child: ExcludeSemantics(
                    child: Material(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox.square(
                                dimension: 58,
                                child: CircularProgressIndicator(
                                  strokeWidth: 5,
                                  color: appLime,
                                  backgroundColor: Color(0x33FFFFFF),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Solicitud en curso',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: appWhite,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 280),
                                child: Text(
                                  _message,
                                  key: ValueKey(_message),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    height: 1.4,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const StatusPill(status: 'BUSCANDO_CONDUCTOR'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientMapTab extends StatefulWidget {
  const _ClientMapTab({
    required this.viewModel,
    required this.draftPickup,
    required this.draftDestination,
  });

  final ClientViewModel viewModel;
  final LatLng? draftPickup;
  final LatLng? draftDestination;

  @override
  State<_ClientMapTab> createState() => _ClientMapTabState();
}

class _ClientMapTabState extends State<_ClientMapTab> {
  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _loadUserLocation();
  }

  Future<void> _loadUserLocation() async {
    final point = await widget.viewModel.currentLocation();
    if (mounted && point != null) {
      setState(() => _userLocation = LatLng(point.latitude, point.longitude));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRequest = widget.viewModel.activeRequest;
    // Sólo los viajes en curso: uno cancelado o terminado no debe seguir
    // dibujado en el mapa.
    final enRuta = widget.viewModel.services
        .where((service) => service.isDrawableOnMap)
        .toList(growable: false);
    final routes = <RouteVisual>[
      for (var i = 0; i < enRuta.length; i++)
        RouteVisual(
          service: enRuta[i],
          color: _clientPalette[i % _clientPalette.length],
        ),
    ];
    final vehicles = <MapVehicleVisual>[
      if (activeRequest != null && activeRequest.hasDriverPosition)
        MapVehicleVisual(
          id: 'client-driver:${activeRequest.id}',
          routeId: activeRequest.id,
          point: LatLng(
            activeRequest.driverLatitude!,
            activeRequest.driverLongitude!,
          ),
          heading: activeRequest.driverHeading ?? 0,
          label:
              '${activeRequest.driverName ?? 'Conductor'} · '
              '${activeRequest.vehiclePlate ?? 'Vehículo asignado'}',
          stale: activeRequest.isDriverLocationStale,
        ),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: OrganicRouteMap(
            routes: routes,
            initialZoom: 13,
            showEmptyMap: true,
            draftPickup: widget.draftPickup,
            draftDestination: widget.draftDestination,
            userLocation: _userLocation,
            vehicles: vehicles,
            followVehicleId: vehicles.isEmpty ? null : vehicles.first.id,
          ),
        ),
        // En el mapa sólo va el conductor asignado, que es lo que el cliente
        // necesita ver mientras espera. El listado de solicitudes vive en su
        // perfil, como historial.
        if (activeRequest != null &&
            activeRequest.hasAssignedDriver &&
            !activeRequest.isSearchingForDriver)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            left: 16,
            right: 16,
            child: _ClientTrackingCard(service: activeRequest),
          ),
      ],
    );
  }
}

class _ClientTrackingCard extends StatelessWidget {
  const _ClientTrackingCard({required this.service});

  final TransportService service;

  @override
  Widget build(BuildContext context) {
    final vehicle = [
      if (service.vehicleModel?.trim().isNotEmpty ?? false)
        service.vehicleModel!.trim(),
      if (service.vehiclePlate?.trim().isNotEmpty ?? false)
        service.vehiclePlate!.trim(),
    ].join(' · ');
    // Antes de arrancar, el tiempo es hasta el punto de recojo; una vez en
    // camino, lo que importa es cuánto falta para llegar al destino.
    final eta = service.etaMinutes == null
        ? 'Calculando tiempo…'
        : service.isUnderway
        ? 'Llegada al destino en ${service.etaMinutes} min'
        : 'Te recoge en ${service.etaMinutes} min';
    return Semantics(
      container: true,
      label:
          'Conductor asignado: ${service.driverName ?? 'Conductor'}. '
          '$vehicle. $eta. Estado ${statusLabel(service.currentStatus)}.',
      child: Material(
        color: appBlack.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: appLime,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_taxi_rounded,
                  color: appBlack,
                  size: 28,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      service.driverName ?? 'Conductor asignado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (vehicle.isNotEmpty)
                      Text(
                        vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(status: service.currentStatus),
                        Text(
                          eta,
                          style: const TextStyle(
                            color: appLime,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (service.driverPhone != null) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Llamar al conductor',
                  onPressed: () => unawaited(_callDriver(service.driverPhone!)),
                  style: IconButton.styleFrom(
                    backgroundColor: appWhite,
                    foregroundColor: appBlack,
                    minimumSize: const Size.square(52),
                  ),
                  icon: const Icon(Icons.call_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return;
    await launchUrl(
      Uri(scheme: 'tel', path: normalized),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _RequestsPanel extends StatelessWidget {
  const _RequestsPanel({required this.viewModel, required this.onRefresh});

  final ClientViewModel viewModel;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final services = [...viewModel.services]
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return Material(
      color: appBlack.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list_alt_rounded, color: appWhite, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Mis solicitudes',
                    style: TextStyle(
                      color: appWhite,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (viewModel.services.isNotEmpty)
                  Text(
                    '${viewModel.services.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                IconButton(
                  tooltip: 'Actualizar solicitudes',
                  onPressed: viewModel.loadingServices ? null : onRefresh,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  icon: viewModel.loadingServices
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: appWhite,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: appWhite,
                          size: 20,
                        ),
                ),
              ],
            ),
            if (viewModel.servicesError != null && services.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 6, 8, 2),
                child: Text(
                  'No pudimos verificar tus solicitudes activas. Actualiza antes de solicitar.',
                  style: TextStyle(
                    color: Color(0xFFFFD166),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (services.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 6, 8, 2),
                child: Text(
                  'Aún no tienes solicitudes. Usa “Solicitar” para pedir un viaje.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: services.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0x33FFFFFF)),
                  itemBuilder: (context, index) {
                    final service = services[index];
                    return Padding(
                      padding: const EdgeInsets.only(top: 7, bottom: 7),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.route_rounded,
                            color: appLime,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${service.code} · '
                                  '${statusLabel(service.currentStatus)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: appWhite,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  service.destinationAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  formatDateTime(service.scheduledAt),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClientProfileTab extends StatelessWidget {
  const _ClientProfileTab({required this.viewModel, required this.onSettings});

  final ClientViewModel viewModel;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final user = viewModel.user;
    final name = user?.fullName ?? 'Cliente';
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
                  child: Center(child: _ClientAvatar(name: name)),
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
                        'CLIENTE',
                        style: TextStyle(
                          color: appLime,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Image.asset(
                        'assets/images/logo_centinela.png',
                        width: 13,
                        height: 13,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'INFORMACIÓN DEL CLIENTE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: appWhite,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                _ClientProfileLine(
                  icon: Icons.person_outline_rounded,
                  value: name,
                ),
                const SizedBox(height: 14),
                _ClientProfileLine(
                  icon: Icons.mail_outline_rounded,
                  value: user?.email ?? '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Historial de solicitudes, al pie del perfil.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _RequestsPanel(
              viewModel: viewModel,
              onRefresh: viewModel.loadServices,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.name});

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
    return Container(
      width: 172,
      height: 172,
      padding: const EdgeInsets.all(5),
      decoration: const BoxDecoration(color: appWhite, shape: BoxShape.circle),
      child: ClipOval(
        child: ColoredBox(
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
        ),
      ),
    );
  }
}

class _ClientSettingsSheet extends StatelessWidget {
  const _ClientSettingsSheet({required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ajustes',
                    style: TextStyle(
                      color: appBlack,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1EE),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: appBlack,
                    ),
                    title: const Text(
                      'Ubicación',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text(
                      'Configura el permiso para usar tu ubicación.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _requestLocation(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.notifications_outlined,
                      color: appBlack,
                    ),
                    title: const Text(
                      'Notificaciones',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text(
                      'Recibe novedades sobre tus solicitudes.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _requestNotifications(context),
                  ),
                  const Divider(height: 1),
                  ValueListenableBuilder<MapTheme>(
                    valueListenable: mapThemeController,
                    builder: (context, mapTheme, _) => ListTile(
                      leading: const Icon(
                        Icons.layers_outlined,
                        color: appBlack,
                      ),
                      title: const Text(
                        'Tema del mapa',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text('Actualmente: ${mapTheme.label}.'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showMapThemePicker(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
    );
  }

  Future<void> _requestLocation(BuildContext context) async {
    try {
      await AppScope.of(
        context,
        listen: false,
      ).locationService.currentLocation();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ubicación habilitada.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _requestNotifications(BuildContext context) async {
    await AppScope.of(
      context,
      listen: false,
    ).authRepository.requestNotificationPermission();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permiso de notificaciones actualizado.')),
    );
  }
}

class _ClientProfileLine extends StatelessWidget {
  const _ClientProfileLine({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: appLime, size: 20),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: appWhite, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class ClientRequestSheet extends StatefulWidget {
  const ClientRequestSheet({
    required this.viewModel,
    required this.onPickupPointChanged,
    required this.onDestinationPointChanged,
    super.key,
  });

  final ClientViewModel viewModel;
  final ValueChanged<LatLng?> onPickupPointChanged;
  final ValueChanged<LatLng?> onDestinationPointChanged;

  @override
  State<ClientRequestSheet> createState() => _ClientRequestSheetState();
}

class _ClientRequestSheetState extends State<ClientRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _notes = TextEditingController();

  LatLng? _pickupPoint;
  String? _pickupError;
  bool _locating = false;
  LatLng? _destPoint;
  String? _destError;
  bool _geocoding = false;
  bool _submitting = false;
  bool _completed = false;
  late final DateTime _scheduledAt;
  String? _requestError;

  @override
  void initState() {
    super.initState();
    _scheduledAt = DateTime.now().add(const Duration(minutes: 30));
    _locate();
  }

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _pickupPoint = null;
      _pickupError = null;
    });
    widget.onPickupPointChanged(null);
    final location = await widget.viewModel.currentLocation();
    if (!mounted) return;
    if (location == null) {
      setState(() {
        _locating = false;
        _pickupError =
            widget.viewModel.lastLocationFailure ??
            'No se pudo obtener tu ubicación. Revisa que el GPS esté activo.';
      });
      return;
    }

    final point = LatLng(location.latitude, location.longitude);
    final address = await widget.viewModel.reverseGeocode(point);
    if (!mounted) return;
    if (address == null) {
      setState(() {
        _locating = false;
        _pickupError =
            widget.viewModel.lastLocationFailure ??
            'No pudimos identificar la dirección. Escríbela manualmente.';
      });
      return;
    }

    _origin.text = address;
    setState(() {
      _locating = false;
      _pickupPoint = point;
    });
    widget.onPickupPointChanged(point);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (widget.viewModel.hasActiveRequest) {
      setState(() {
        _requestError =
            'Ya tienes una solicitud activa. Espera a que finalice antes de crear otra.';
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _pickupError = null;
      _destError = null;
      _requestError = null;
    });

    var pickup = _pickupPoint;
    if (pickup == null) {
      setState(() => _geocoding = true);
      pickup = await widget.viewModel.geocode(_origin.text.trim());
      if (!mounted) return;
      if (pickup == null) {
        setState(() {
          _submitting = false;
          _geocoding = false;
          _pickupError =
              'No encontramos ese origen. Agrega distrito, ciudad y país.';
        });
        return;
      }
      widget.onPickupPointChanged(pickup);
    }

    var destination = _destPoint;
    if (destination == null) {
      setState(() => _geocoding = true);
      destination = await widget.viewModel.geocode(_destination.text.trim());
      if (!mounted) return;
      if (destination == null) {
        setState(() {
          _submitting = false;
          _geocoding = false;
          _destError =
              'No encontramos esa dirección. Agrega distrito, ciudad y país.';
        });
        return;
      }
      widget.onDestinationPointChanged(destination);
    }

    if (mounted) {
      setState(() => _geocoding = false);
    }
    final service = await widget.viewModel.submitRequest(
      pickup: pickup,
      pickupAddress: _origin.text.trim(),
      destination: destination,
      destinationAddress: _destination.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      scheduledAt: _scheduledAt,
    );
    if (!mounted) return;
    if (service == null) {
      setState(() {
        _submitting = false;
        _geocoding = false;
        _requestError = _friendlyClientError(widget.viewModel.submissionError);
      });
      return;
    }

    setState(() {
      _submitting = false;
      _geocoding = false;
      _completed = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (mounted) Navigator.pop(context, true);
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
                key: ValueKey('request-submitted'),
                height: 340,
                child: _RequestConfirmation(),
              )
            : SafeArea(
                key: const ValueKey('request-form'),
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
                                Icons.add_location_alt_rounded,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Solicitar servicio',
                                    style: sheetTheme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    'Salida programada para '
                                    '${formatDateTime(_scheduledAt)}.',
                                    style: const TextStyle(
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
                        const SizedBox(height: 14),
                        AddressAutocompleteField(
                          controller: _origin,
                          label: 'Origen',
                          icon: Icons.my_location_rounded,
                          routingService: widget.viewModel.roadRoutingService,
                          errorText: _pickupError,
                          validator: (value) => (value?.trim().length ?? 0) < 6
                              ? 'Escribe una dirección completa.'
                              : null,
                          onPointChanged: (point) {
                            setState(() {
                              _pickupPoint = point;
                              _pickupError = null;
                            });
                            widget.onPickupPointChanged(point);
                          },
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _locating ? null : _locate,
                            icon: _locating
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: appBlack,
                                    ),
                                  )
                                : const Icon(Icons.gps_fixed_rounded, size: 18),
                            label: const Text('Usar mi ubicación'),
                          ),
                        ),
                        AddressAutocompleteField(
                          controller: _destination,
                          label: 'Destino',
                          icon: Icons.flag_rounded,
                          routingService: widget.viewModel.roadRoutingService,
                          errorText: _destError,
                          validator: (value) => (value?.trim().length ?? 0) < 6
                              ? 'Escribe una dirección completa.'
                              : null,
                          onPointChanged: (point) {
                            setState(() {
                              _destPoint = point;
                              _destError = null;
                            });
                            if (point != null) {
                              widget.onDestinationPointChanged(point);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          textInputAction: TextInputAction.done,
                          maxLines: 1,
                          style: const TextStyle(color: appBlack),
                          decoration: const InputDecoration(
                            labelText: 'Notas (opcional)',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                        ),
                        if (_requestError != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: appBlack,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _requestError!,
                                  style: const TextStyle(
                                    color: Color(0xFF444444),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed:
                                _submitting || widget.viewModel.hasActiveRequest
                                ? null
                                : _submit,
                            child: _submitting
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: appBlack,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          _geocoding
                                              ? 'Buscando dirección…'
                                              : 'Enviando solicitud…',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text('Solicitar servicio'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _RequestConfirmation extends StatelessWidget {
  const _RequestConfirmation();

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
            'Solicitud enviada',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Estamos procesando tu solicitud. Verás el estado y la '
            'asignación del conductor sobre el mapa.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }
}

String _friendlyClientError(String? message) {
  final normalized = (message ?? '').toLowerCase();
  if (normalized.contains('socketexception') ||
      normalized.contains('connection') ||
      normalized.contains('timed out') ||
      normalized.contains('no se pudo conectar')) {
    return 'No se pudo enviar la solicitud. Revisa tu conexión e intenta '
        'nuevamente.';
  }
  return (message ?? 'No se pudo enviar la solicitud.').replaceFirst(
    'Exception: ',
    '',
  );
}

/// Aviso de que el viaje arrancó: círculo azul con un check blanco.
///
/// Se cierra solo a los pocos segundos para devolver el mapa, donde el cliente
/// sigue a su conductor. También se puede cerrar tocando.
class _ServiceStartedOverlay extends StatefulWidget {
  const _ServiceStartedOverlay({required this.onDone, this.driverName});

  final VoidCallback onDone;
  final String? driverName;

  @override
  State<_ServiceStartedOverlay> createState() => _ServiceStartedOverlayState();
}

class _ServiceStartedOverlayState extends State<_ServiceStartedOverlay> {
  Timer? _cierre;

  @override
  void initState() {
    super.initState();
    _cierre = Timer(const Duration(seconds: 4), widget.onDone);
  }

  @override
  void dispose() {
    _cierre?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conductor = widget.driverName;
    return GestureDetector(
      onTap: widget.onDone,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: appLime,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: appWhite,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Tu servicio inició',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: appWhite,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  conductor == null
                      ? 'Ya puedes seguir tu viaje en el mapa.'
                      : '$conductor ya está en camino. Sigue el viaje en el mapa.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFD7D7D2), height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
