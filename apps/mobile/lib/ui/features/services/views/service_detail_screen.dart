import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/repositories/notification_repository.dart';
import '../../../../domain/models/transport_service.dart';
import '../../../core/app_bottom_sheet.dart';
import '../../../core/app_emergency_sheet.dart';
import '../../../core/app_scope.dart';
import '../../../core/app_success_overlay.dart';
import '../../../core/app_theme.dart';
import '../../../core/date_formats.dart';
import '../../../core/status_styles.dart';
import '../../summary/views/service_summary_screen.dart';
import '../view_models/service_detail_view_model.dart';

class ServiceDetailSheet extends StatefulWidget {
  const ServiceDetailSheet({
    required this.serviceId,
    this.onClose,
    this.onRouteStarted,
    this.onRouteStopped,
    this.onCollapsedChanged,
    this.dedicatedDriver = false,
    super.key,
  });

  final String serviceId;
  final VoidCallback? onClose;
  final VoidCallback? onRouteStarted;
  final VoidCallback? onRouteStopped;
  final ValueChanged<bool>? onCollapsedChanged;
  final bool dedicatedDriver;

  @override
  State<ServiceDetailSheet> createState() => _ServiceDetailSheetState();
}

class _ServiceDetailSheetState extends State<ServiceDetailSheet> {
  late final ServiceDetailViewModel _viewModel;
  late final NotificationRepository _notificationRepository;
  bool _collapsed = false;
  String? _emergencyError;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context, listen: false);
    _notificationRepository = scope.notificationRepository;
    _viewModel = ServiceDetailViewModel(
      serviceId: widget.serviceId,
      serviceRepository: scope.serviceRepository,
      eventRepository: scope.eventRepository,
      evidenceRepository: scope.evidenceRepository,
      locationService: scope.locationService,
      backgroundTrackingService: scope.backgroundTrackingService,
      syncCoordinator: scope.syncCoordinator,
      authRepository: scope.authRepository,
      trackingRepository: scope.trackingRepository,
      roadRoutingService: scope.roadRoutingService,
      dedicatedDriverHint: widget.dedicatedDriver,
    );
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final service = _viewModel.service;
        final collapsed = _collapsed && _viewModel.isRouteActive;
        final content = switch (service) {
          null when _viewModel.isLoading => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          null => SizedBox(
            height: 200,
            child: _UnavailableState(onRetry: _viewModel.load),
          ),
          _ when collapsed => SizedBox(
            height: 72,
            child: _CollapsedServiceDetail(
              service: service,
              onExpand: () => _setCollapsed(false),
              onClose: widget.onClose,
            ),
          ),
          _ => _ServiceContent(
            service: service,
            viewModel: _viewModel,
            onClose: widget.onClose,
            onCollapse: _viewModel.isRouteActive
                ? () => _setCollapsed(true)
                : null,
            onAction: _performAction,
            onBeginRoute: _beginRoute,
            onOpenRoute: _openRouteInGoogleMaps,
            onDedicatedStop: _registerDedicatedStop,
            onDedicatedFinish: _finishDedicatedDuty,
            onEmergency: _confirmEmergency,
          ),
        };
        return AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: ColoredBox(
            color: appWhite,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.88,
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }

  void _setCollapsed(bool value) {
    if (_collapsed == value) return;
    setState(() => _collapsed = value);
    widget.onCollapsedChanged?.call(value);
  }

  Future<void> _performAction(ServiceAction action) async {
    switch (action) {
      case ServiceAction.stop:
        final input = await _showStopDialog();
        if (input == null) return;
        await _viewModel.registerStop(
          reasonCode: input.reasonCode,
          notes: input.notes,
        );
        // La parada es instantánea: el check es lo único que le confirma al
        // conductor que quedó anotada.
        if (mounted && _viewModel.errorMessage == null) {
          await showAppSuccessOverlay(context, title: 'Parada registrada');
        }
      case ServiceAction.incident:
        final input = await _showIncidentDialog();
        if (input == null) return;
        await _viewModel.reportIncident(
          incidentType: input.type,
          severity: input.severity,
          description: input.description,
          attachPhoto: input.attachPhoto,
        );
      case ServiceAction.suspend:
        final reason = await _showReasonDialog(
          title: 'Suspender servicio',
          hint: 'Motivo de la suspensión',
        );
        if (reason == null) return;
        await _viewModel.suspend(reason);
      case ServiceAction.finish:
        final confirmed = await _confirmFinish();
        if (!confirmed) return;
        await _viewModel.executeSimple(action);
      case ServiceAction.summary:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ServiceSummaryScreen(serviceId: widget.serviceId),
          ),
        );
      default:
        await _viewModel.executeSimple(action);
    }
    if (!mounted || _viewModel.errorMessage != null) return;
    if (action == ServiceAction.start) widget.onRouteStarted?.call();
    if (action == ServiceAction.finish) widget.onRouteStopped?.call();
  }

  Future<void> _beginRoute() async {
    await _viewModel.beginRoute();
    if (!mounted || _viewModel.errorMessage != null) return;
    // Ya no hay espera a entrar en la geocerca del origen: iniciar arranca.
    if (_viewModel.routeStarted) widget.onRouteStarted?.call();
  }

  Future<void> _registerDedicatedStop() async {
    await _viewModel.registerDedicatedStop();
    if (!mounted || _viewModel.errorMessage != null) return;
    await showAppSuccessOverlay(context, title: 'Parada registrada');
  }

  Future<void> _finishDedicatedDuty() async {
    final confirmed = await _confirmFinish();
    if (!confirmed) return;
    await _viewModel.finishDedicatedDuty();
    if (!mounted || _viewModel.errorMessage != null) return;
    widget.onRouteStopped?.call();
  }

  Future<void> _openRouteInGoogleMaps() async {
    final service = _viewModel.service;
    if (service?.pickupLatitude == null ||
        service?.pickupLongitude == null ||
        service?.destinationLatitude == null ||
        service?.destinationLongitude == null) {
      _showMapError('La ruta no tiene coordenadas completas.');
      return;
    }
    final opened = await _openGoogleMaps(
      origin: '${service!.pickupLatitude},${service.pickupLongitude}',
      destination:
          '${service.destinationLatitude},${service.destinationLongitude}',
    );
    if (!opened && mounted) {
      _showMapError('No se pudo abrir Google Maps.');
    }
  }

  void _showMapError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// SOS desde el propio servicio. El aviso viaja con el `serviceId`, así el
  /// panel sabe en qué viaje estaba el conductor sin tener que cruzarlo a mano.
  Future<void> _confirmEmergency() async {
    _emergencyError = null;
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => AppEmergencySheet(
        onSend: _sendEmergency,
        errorMessage: () => _emergencyError,
      ),
    );
  }

  Future<bool> _sendEmergency() async {
    try {
      await _notificationRepository.sendEmergency(serviceId: widget.serviceId);
      _emergencyError = null;
      return true;
    } catch (_) {
      _emergencyError =
          'No se pudo enviar la alerta. Intenta nuevamente o llama a emergencias.';
      return false;
    }
  }

  Future<_StopInput?> _showStopDialog() async {
    String reason = 'REST';
    final notes = TextEditingController();
    final result = await showDialog<_StopInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar parada'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Motivo'),
                items: const [
                  DropdownMenuItem(value: 'REST', child: Text('Descanso')),
                  DropdownMenuItem(value: 'FUEL', child: Text('Combustible')),
                  DropdownMenuItem(value: 'PASSENGER', child: Text('Pasajero')),
                  DropdownMenuItem(
                    value: 'MECHANICAL',
                    child: Text('Revisión mecánica'),
                  ),
                  DropdownMenuItem(value: 'OTHER', child: Text('Otro')),
                ],
                onChanged: (value) =>
                    setDialogState(() => reason = value ?? reason),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Nota opcional'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _StopInput(reasonCode: reason, notes: notes.text),
              ),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
    return result;
  }

  Future<_IncidentInput?> _showIncidentDialog() async {
    String type = 'OTHER';
    String severity = 'MEDIUM';
    bool attachPhoto = false;
    final description = TextEditingController();
    final result = await showDialog<_IncidentInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reportar incidencia'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(
                      value: 'PASSENGER_ABSENT',
                      child: Text('Pasajero ausente'),
                    ),
                    DropdownMenuItem(value: 'DELAY', child: Text('Retraso')),
                    DropdownMenuItem(
                      value: 'CANCELLATION',
                      child: Text('Cancelación'),
                    ),
                    DropdownMenuItem(value: 'BREAKDOWN', child: Text('Avería')),
                    DropdownMenuItem(
                      value: 'ROUTE_CHANGE',
                      child: Text('Cambio de ruta'),
                    ),
                    DropdownMenuItem(value: 'OTHER', child: Text('Otra')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? type),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severidad'),
                  items: const [
                    DropdownMenuItem(value: 'LOW', child: Text('Baja')),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('Media')),
                    DropdownMenuItem(value: 'HIGH', child: Text('Alta')),
                    DropdownMenuItem(value: 'CRITICAL', child: Text('Crítica')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => severity = value ?? severity),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Descripción obligatoria',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: attachPhoto,
                  title: const Text('Adjuntar foto'),
                  subtitle: const Text('Se abrirá la cámara al continuar.'),
                  onChanged: (value) =>
                      setDialogState(() => attachPhoto = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: description.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      _IncidentInput(
                        type: type,
                        severity: severity,
                        description: description.text.trim(),
                        attachPhoto: attachPhoto,
                      ),
                    ),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    description.dispose();
    return result;
  }

  Future<String?> _showReasonDialog({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirmFinish() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Finalizar servicio'),
            content: Text(
              _viewModel.isDedicatedDuty
                  ? 'Al confirmar se capturará tu ubicación final y se cerrará el seguimiento GPS.'
                  : 'Confirma que el servicio terminó. El servidor cerrará la sesión de seguimiento.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Finalizar'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _ServiceContent extends StatelessWidget {
  const _ServiceContent({
    required this.service,
    required this.viewModel,
    required this.onClose,
    required this.onCollapse,
    required this.onAction,
    required this.onBeginRoute,
    required this.onOpenRoute,
    required this.onDedicatedStop,
    required this.onDedicatedFinish,
    required this.onEmergency,
  });

  final TransportService service;
  final ServiceDetailViewModel viewModel;
  final VoidCallback? onClose;
  final VoidCallback? onCollapse;
  final Future<void> Function(ServiceAction action) onAction;
  final Future<void> Function() onBeginRoute;
  final Future<void> Function() onOpenRoute;
  final Future<void> Function() onDedicatedStop;
  final Future<void> Function() onDedicatedFinish;
  final Future<void> Function() onEmergency;

  @override
  Widget build(BuildContext context) {
    final date = formatDateTime(service.scheduledAt);
    final actions = viewModel.isDedicatedDuty
        ? const <ServiceAction>[]
        : service.allowedActions
              .where((action) => !viewModel.isPreStartAction(action))
              .toList();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFBBBFB2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (viewModel.isLoading)
              const LinearProgressIndicator(minHeight: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.code,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$date · ${service.vehiclePlate ?? 'Sin unidad'}',
                        style: const TextStyle(
                          color: Color(0xFF686864),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: statusLabel(service.currentStatus),
                  hasIncident: service.hasOpenIncident,
                ),
                // Rojo y siempre presente: durante el viaje el conductor no
                // debería tener que salir del servicio para pedir auxilio.
                IconButton(
                  tooltip: 'Emergencia',
                  onPressed: onEmergency,
                  style: IconButton.styleFrom(
                    backgroundColor: appEmergency,
                    foregroundColor: appWhite,
                  ),
                  icon: const Icon(Icons.sos_rounded),
                ),
                if (onCollapse != null)
                  IconButton(
                    tooltip: 'Minimizar detalle',
                    onPressed: onCollapse,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Cerrar detalle',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (viewModel.isDedicatedDuty)
              _DedicatedDutySummary(service: service)
            else
              _RouteSummary(service: service),
            if (viewModel.errorMessage != null) ...[
              const SizedBox(height: 10),
              _Feedback(message: viewModel.errorMessage!, isError: true),
            ] else if (viewModel.message != null) ...[
              const SizedBox(height: 10),
              _Feedback(message: viewModel.message!, isError: false),
            ],
            if (viewModel.isDedicatedDuty) ...[
              const SizedBox(height: 20),
              _DedicatedDutyActions(
                viewModel: viewModel,
                onStop: onDedicatedStop,
                onFinish: onDedicatedFinish,
              ),
            ] else ...[
              const SizedBox(height: 20),
              if (viewModel.canBeginRoute) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        viewModel.isLoading ||
                            viewModel.hasBlockingFailure ||
                            viewModel.hasPendingCommand
                        ? null
                        : onBeginRoute,
                    child: const Text('Iniciar ruta'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (viewModel.isRouteActive) ...[
                SizedBox(
                  width: double.infinity,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact =
                          constraints.maxWidth < 320 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.2;
                      final style = FilledButton.styleFrom(
                        backgroundColor: appBlack,
                        foregroundColor: appLime,
                      );
                      if (compact) {
                        return FilledButton(
                          onPressed: onOpenRoute,
                          style: style,
                          child: const Text(
                            'Abrir ruta en Google Maps',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }
                      return FilledButton.icon(
                        onPressed: onOpenRoute,
                        style: style,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Abrir ruta en Google Maps'),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'Acciones disponibles',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (viewModel.hasPendingCommand) ...[
                const _Feedback(
                  message:
                      'Hay una operación pendiente. Se habilitarán nuevas acciones después del ACK del servidor.',
                  isError: false,
                ),
                const SizedBox(height: 10),
              ],
              if (viewModel.hasBlockingFailure) ...[
                const _Feedback(
                  message:
                      'Hay una operación rechazada. Las acciones quedan bloqueadas hasta reconciliarla con soporte.',
                  isError: true,
                ),
                const SizedBox(height: 10),
              ],
              if (actions.isEmpty)
                const Text('No hay acciones habilitadas por el servidor.')
              else
                for (final action in actions) ...[
                  _ActionButton(
                    action: action,
                    enabled:
                        !viewModel.isLoading &&
                        !viewModel.hasBlockingFailure &&
                        !viewModel.hasPendingCommand,
                    onPressed: () => onAction(action),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CollapsedServiceDetail extends StatelessWidget {
  const _CollapsedServiceDetail({
    required this.service,
    required this.onExpand,
    required this.onClose,
  });

  final TransportService service;
  final VoidCallback onExpand;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 10, 4),
        child: Row(
          children: [
            const Icon(Icons.navigation_rounded, color: appLime, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.code,
                    style: const TextStyle(
                      color: appBlack,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    statusLabel(service.currentStatus),
                    style: const TextStyle(
                      color: Color(0xFF555551),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              tooltip: 'Expandir detalle',
              onPressed: onExpand,
              style: IconButton.styleFrom(
                backgroundColor: appLime,
                foregroundColor: appWhite,
              ),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Cerrar detalle',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _DedicatedDutySummary extends StatelessWidget {
  const _DedicatedDutySummary({required this.service});

  final TransportService service;

  @override
  Widget build(BuildContext context) {
    final ordered = [...service.waypoints]
      ..sort((first, second) => first.ordinal.compareTo(second.ordinal));
    final starts = ordered.where(
      (waypoint) => waypoint.type == DedicatedWaypointType.start,
    );
    final start = starts.isEmpty ? null : starts.first;
    final stops = service.dedicatedStops;
    return Semantics(
      label: 'Resumen del servicio dedicado',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1EE),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.route_rounded, color: appBlack),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'SERVICIO DEDICADO',
                    style: TextStyle(
                      color: appBlack,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (start != null) ...[
              const SizedBox(height: 14),
              _DedicatedWaypointLine(
                icon: Icons.play_circle_outline_rounded,
                title: 'Inicio',
                address: start.address,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              stops.isEmpty
                  ? 'Aún no registraste paradas.'
                  : 'Paradas registradas (${stops.length})',
              style: const TextStyle(
                color: appBlack,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (stops.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var index = 0; index < stops.length; index++) ...[
                _DedicatedWaypointLine(
                  icon: Icons.location_on_outlined,
                  title: 'Parada ${index + 1}',
                  address: stops[index].address,
                ),
                if (index != stops.length - 1)
                  const Divider(height: 20, color: Color(0xFFD6D6D1)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DedicatedWaypointLine extends StatelessWidget {
  const _DedicatedWaypointLine({
    required this.icon,
    required this.title,
    required this.address,
  });

  final IconData icon;
  final String title;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: appBlack),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: appBlack,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(address, style: const TextStyle(color: Color(0xFF5F5F5A))),
            ],
          ),
        ),
      ],
    );
  }
}

class _DedicatedDutyActions extends StatelessWidget {
  const _DedicatedDutyActions({
    required this.viewModel,
    required this.onStop,
    required this.onFinish,
  });

  final ServiceDetailViewModel viewModel;
  final Future<void> Function() onStop;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    if (!viewModel.isDedicatedDutyActive) {
      return const Text(
        'Este servicio dedicado ya no está activo.',
        style: TextStyle(color: Color(0xFF5F5F5A), fontWeight: FontWeight.w700),
      );
    }
    final enabled = !viewModel.isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acciones del servicio',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (!viewModel.isTracking) ...[
          _Feedback(
            message:
                viewModel.trackingError ??
                'El seguimiento GPS no está activo. Reactívalo para continuar registrando el recorrido.',
            isError: true,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: enabled ? viewModel.retryTracking : null,
              icon: const Icon(Icons.gps_fixed_rounded),
              label: const Text('Reactivar seguimiento GPS'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const ValueKey('register-dedicated-stop'),
            onPressed: enabled ? onStop : null,
            icon: viewModel.isRegisteringDedicatedStop
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: appWhite,
                    ),
                  )
                : const Icon(Icons.add_location_alt_outlined),
            label: Text(
              viewModel.isRegisteringDedicatedStop
                  ? 'Registrando parada…'
                  : 'Registrar parada',
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const ValueKey('finish-dedicated-service'),
            onPressed: enabled ? onFinish : null,
            style: FilledButton.styleFrom(
              backgroundColor: appBlack,
              foregroundColor: appWhite,
            ),
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('Finalizar servicio'),
          ),
        ),
      ],
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.service});

  final TransportService service;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RUTA PLANIFICADA',
            style: TextStyle(
              color: appBlack,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'No representa el recorrido GPS realizado.',
            style: TextStyle(color: Color(0xFF686864), fontSize: 12),
          ),
          const SizedBox(height: 12),
          _PlaceLine(
            icon: Icons.radio_button_checked_rounded,
            value: service.pickupAddress,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _PlaceLine(
            icon: Icons.location_on_rounded,
            value: service.destinationAddress,
          ),
          if (service.originGeofence != null ||
              service.destinationGeofence != null) ...[
            const SizedBox(height: 12),
            Text(
              'Geocercas: origen ${service.originGeofence?.radiusMeters.toStringAsFixed(0) ?? '—'} m · '
              'destino ${service.destinationGeofence?.radiusMeters.toStringAsFixed(0) ?? '—'} m',
              style: const TextStyle(
                color: Color(0xFF686864),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.enabled,
    required this.onPressed,
  });

  final ServiceAction action;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final destructive = action == ServiceAction.suspend;
    final style = destructive
        ? FilledButton.styleFrom(
            backgroundColor: appBlack,
            foregroundColor: appLime,
          )
        : null;
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.2;
          final label = Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          );
          if (compact) {
            return FilledButton(
              onPressed: enabled ? onPressed : null,
              style: style,
              child: label,
            );
          }
          return FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            style: style,
            icon: Icon(_icon(action)),
            label: label,
          );
        },
      ),
    );
  }

  IconData _icon(ServiceAction action) => switch (action) {
    ServiceAction.start => Icons.play_arrow_rounded,
    ServiceAction.stop => Icons.pause_circle_outline_rounded,
    ServiceAction.incident => Icons.report_problem_outlined,
    ServiceAction.finish => Icons.task_alt_rounded,
    ServiceAction.suspend => Icons.block_rounded,
    ServiceAction.summary => Icons.summarize_outlined,
  };
}

class _PlaceLine extends StatelessWidget {
  const _PlaceLine({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: appBlack),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: appBlack,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.hasIncident});

  final String label;
  final bool hasIncident;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: hasIncident ? const Color(0xFFFFC6BF) : const Color(0xFFE7E7E3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        hasIncident ? '$label · incidencia' : label,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(
          color: isError ? const Color(0xFF9B1C1C) : const Color(0xFF3E5900),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
    );
  }
}

class _StopInput {
  const _StopInput({required this.reasonCode, required this.notes});

  final String reasonCode;
  final String notes;
}

class _IncidentInput {
  const _IncidentInput({
    required this.type,
    required this.severity,
    required this.description,
    required this.attachPhoto,
  });

  final String type;
  final String severity;
  final String description;
  final bool attachPhoto;
}

Future<bool> _openGoogleMaps({
  String? origin,
  required String destination,
}) async {
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': ?origin,
    'destination': destination,
    'travelmode': 'driving',
  });
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
