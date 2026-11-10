import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../data/repositories/parking_repository.dart';
import '../../../../domain/models/parking_space.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../data/services/parking_location_service.dart';
import '../../../core/app_theme.dart';
import '../../../core/app_bottom_nav.dart';
import '../../../core/app_bottom_sheet.dart';
import '../../../core/map_theme.dart';
import '../../../core/copilot_activation_surface.dart';
import '../../auth/views/login_screen.dart';
import '../view_models/parking_view_model.dart';
import '../view_models/copilot_view_model.dart';
import 'copilot_sheet.dart';
import 'parking_map.dart';
import 'parking_widgets.dart';
import 'nearby_search_sheet.dart';
import '../view_models/nearby_search_view_model.dart';
import 'parking_account_screens.dart';

String money(Object? cents) =>
    'S/ ${(num.parse('$cents') / 100).toStringAsFixed(2)}';
String lima(Object? date) {
  final d = DateTime.parse('$date').toUtc().subtract(const Duration(hours: 5));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)} (Lima)';
}

class ParkLinkApp extends StatelessWidget {
  const ParkLinkApp({required this.repository, super.key});
  final ParkingRepository repository;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository,
    builder: (context, _) => MaterialApp(
      title: 'ParkLink',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: repository.authenticated
          ? ParkingShell(repository: repository)
          : Builder(
              builder: (context) => LoginScreen(
                onLogin: repository.login,
                onRegister: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RegistrationScreen(repository: repository),
                  ),
                ),
              ),
            ),
    ),
  );
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({required this.repository, super.key});
  final ParkingRepository repository;
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool owner = false, busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear cuenta')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Nombre'),
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Correo'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: password,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            helperText: 'Mínimo 12 caracteres',
          ),
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
        ),
        SwitchListTile(
          title: const Text('También quiero publicar estacionamientos'),
          value: owner,
          onChanged: busy ? null : (v) => setState(() => owner = v),
        ),
        if (error != null) Text(error!, semanticsLabel: error),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.repository.register(
                      name.text.trim(),
                      email.text.trim(),
                      password.text,
                      owner,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  } on Object catch (e) {
                    if (mounted) setState(() => error = e.toString());
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Creando cuenta…' : 'Crear cuenta'),
        ),
      ],
    ),
  );
}

class ParkingShell extends StatefulWidget {
  const ParkingShell({required this.repository, super.key});
  final ParkingRepository repository;
  @override
  State<ParkingShell> createState() => _ParkingShellState();
}

class _ParkingShellState extends State<ParkingShell>
    with SingleTickerProviderStateMixin {
  late final ParkingViewModel vm;
  late final CopilotViewModel copilot;
  bool _copilotOpen = false;
  bool _searchOpen = false, _locating = false;
  final map = MapController();
  final location = ParkingLocationService();
  LocationPoint? userLocation;
  int index = 0, reservationGroup = 0;
  late final AnimationController tabAnimation;
  @override
  void initState() {
    super.initState();
    vm = ParkingViewModel(widget.repository);
    copilot = CopilotViewModel(widget.repository);
    tabAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    unawaited(vm.search());
    unawaited(mapThemeController.load());
  }

  @override
  void dispose() {
    vm.dispose();
    copilot.dispose();
    map.dispose();
    tabAnimation.dispose();
    super.dispose();
  }

  Future<void> openCopilot() async {
    if (_copilotOpen || _searchOpen || _locating || !mounted) return;
    _copilotOpen = true;
    copilot.latitude = vm.latitude;
    copilot.longitude = vm.longitude;
    try {
      final selected = await showAppBottomSheet<ParkingSpace>(
        context: context,
        builder: (_) => CopilotSheet(viewModel: copilot),
      );
      if (selected != null && mounted) await booking(selected);
    } finally {
      _copilotOpen = false;
    }
  }

  Future<void> refresh() async {
    if (index == 0) {
      await vm.search();
    }
    if (index == 1) {
      await vm.load('/reservations/mine');
    }
  }

  Future<void> select(int i) async {
    if (i == index) return;
    setState(() => index = i);
    if (!MediaQuery.disableAnimationsOf(context)) {
      tabAnimation.forward(from: .35);
    }
    await refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => CopilotActivationSurface(
      onActivate: openCopilot,
      child: Scaffold(
        extendBody: true,
        body: FadeTransition(
          opacity: tabAnimation,
          child: IndexedStack(
            index: index,
            children: [
              discovery(),
              SafeArea(bottom: false, child: reservations()),
              SafeArea(bottom: false, child: profile()),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: index,
          onDestinationSelected: select,
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
              icon: Icons.search_rounded,
              label: 'Buscar estacionamiento cercano',
              primary: true,
              size: 64,
              onPressed: openSearch,
            ),
          ],
        ),
      ),
    ),
  );
  Widget discovery() => ParkingMap(
    viewModel: vm,
    controller: map,
    onSelect: preview,
    onLocate: locate,
    onFilters: filters,
    onCopilot: openCopilot,
    userLocation: userLocation,
    locating: _locating,
  );

  Future<void> openSearch() async {
    if (_searchOpen || _copilotOpen) return;
    _searchOpen = true;
    final nearby = NearbySearchViewModel(
      widget.repository,
      locationService: location,
      mapCenter: LocationPoint(
        latitude: vm.latitude,
        longitude: vm.longitude,
        accuracy: 0,
      ),
      radius: vm.radius,
      maxRate: vm.maxRate,
      feature: vm.feature,
      text: vm.text,
    );
    try {
      final result = await showAppBottomSheet<NearbyParkingResult>(
        context: context,
        builder: (_) => NearbySearchSheet(viewModel: nearby),
      );
      if (!mounted) return;
      if (nearby.fromDevice && nearby.origin != null) {
        setState(() => userLocation = nearby.origin);
      }
      if (result != null) {
        await booking(result.space, start: result.start, end: result.end);
      }
    } finally {
      nearby.dispose();
      _searchOpen = false;
    }
  }

  Future<void> preview(ParkingSpace space) async {
    if (_searchOpen || _copilotOpen) return;
    _searchOpen = true;
    try {
      final reserve = await showAppBottomSheet<bool>(
        context: context,
        builder: (sheetContext) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  tooltip: 'Cerrar detalle',
                  icon: const Icon(Icons.close),
                ),
              ),
              ParkingResultCard(
                space: space,
                fromDevice: false,
                onReserve: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      );
      if (reserve == true && mounted) await booking(space);
    } finally {
      _searchOpen = false;
    }
  }

  Future<void> locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      LocationPoint point;
      try {
        point = await location.current();
      } on ParkingLocationException catch (e) {
        if (!mounted) return;
        if (e.issue != ParkingLocationIssue.permission) rethrow;
        final allow = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Encuentra lugares cerca de ti'),
            content: const Text(
              'Usamos tu ubicación mientras utilizas la aplicación para centrar el mapa y buscar estacionamientos cercanos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Ahora no'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
        if (allow != true) return;
        point = await location.current(requestPermission: true);
      }
      if (!mounted) return;
      setState(() => userLocation = point);
      map.move(LatLng(point.latitude, point.longitude), 15);
      vm.latitude = point.latitude;
      vm.longitude = point.longitude;
      await vm.search();
    } on ParkingLocationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No pudimos obtener tu ubicación. Puedes seguir explorando el mapa.',
          ),
          action:
              e.issue == ParkingLocationIssue.blocked ||
                  e.issue == ParkingLocationIssue.disabled
              ? SnackBarAction(
                  label: 'Ajustes',
                  onPressed: () => location.openSettings(e.issue),
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> filters() async {
    var rate = vm.maxRate == null ? '' : '${vm.maxRate! / 100}';
    var radius = vm.radius.toDouble();
    var feature = vm.feature;
    var text = vm.text;
    String? validation;
    await showAppBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tu búsqueda',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Cerrar filtros',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                initialValue: text,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Dirección o zona',
                  counterText: '',
                ),
                onChanged: (v) => text = v,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: rate,
                decoration: InputDecoration(
                  labelText: 'Precio máximo por hora (S/)',
                  errorText: validation,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) => rate = v,
              ),
              const SizedBox(height: 24),
              Text('Radio: ${(radius / 1000).toStringAsFixed(1)} km'),
              Slider(
                value: radius,
                min: 500,
                max: 10000,
                divisions: 19,
                onChanged: (v) => update(() => radius = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: feature ?? '',
                decoration: const InputDecoration(labelText: 'Característica'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Todas')),
                  DropdownMenuItem(value: 'covered', child: Text('Techado')),
                  DropdownMenuItem(value: 'security', child: Text('Seguridad')),
                  DropdownMenuItem(value: 'ev', child: Text('Carga eléctrica')),
                  DropdownMenuItem(
                    value: 'accessible',
                    child: Text('Accesible'),
                  ),
                ],
                onChanged: (v) => feature = v == '' ? null : v,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  final parsed = double.tryParse(rate.replaceAll(',', '.'));
                  if (rate.trim().isNotEmpty &&
                      (parsed == null ||
                          !parsed.isFinite ||
                          parsed <= 0 ||
                          parsed > 10000)) {
                    update(
                      () => validation =
                          'Introduce un precio entre S/ 0.01 y S/ 10 000.',
                    );
                    return;
                  }
                  vm.maxRate = parsed == null ? null : (parsed * 100).round();
                  vm.radius = radius.round();
                  vm.feature = feature;
                  vm.text = text.trim();
                  Navigator.pop(context);
                  unawaited(vm.search());
                },
                child: const Text('Aplicar filtros'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  vm.text = '';
                  vm.maxRate = null;
                  vm.feature = null;
                  vm.radius = 5000;
                  Navigator.pop(context);
                  unawaited(vm.search());
                },
                child: const Text('Restablecer búsqueda'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> booking(
    ParkingSpace space, {
    DateTime? start,
    DateTime? end,
  }) async {
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => BookingSheet(
        space: space,
        repository: widget.repository,
        initialStart: start,
        initialEnd: end,
      ),
    );
    if (mounted) await refresh();
  }

  int group(Map<String, dynamic> r) {
    if (!['PENDING_PAYMENT', 'CONFIRMED', 'ACTIVE'].contains(r['status'])) {
      return 2;
    }
    final end = DateTime.tryParse('${r['end_time']}');
    if (end != null && end.isBefore(DateTime.now())) return 2;
    return DateTime.parse('${r['start_time']}').isAfter(DateTime.now()) ? 1 : 0;
  }

  Widget reservations() {
    final rows = vm.records.where((r) => group(r) == reservationGroup).toList();
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        children: [
          const ParkingSectionTitle(
            'Tus reservas',
            subtitle: 'Todo listo para tu próximo viaje.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, label) in [
                'Activas',
                'Próximas',
                'Anteriores',
              ].indexed)
                ChoiceChip(
                  label: Text(label),
                  selected: reservationGroup == i,
                  onSelected: (_) => setState(() => reservationGroup = i),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (vm.error != null) ParkingNotice(vm.error!, onRetry: refresh),
          if (vm.busy)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (rows.isEmpty && !vm.busy && vm.error == null)
            ParkingEmptyState(
              icon: Icons.receipt_long_outlined,
              title: [
                'No tienes reservas activas',
                'Tu próximo espacio te espera',
                'Aún no hay reservas anteriores',
              ][reservationGroup],
              message:
                  'Encuentra un estacionamiento y revisa el horario antes de reservar.',
              action: FilledButton(
                onPressed: openSearch,
                child: const Text('Encontrar estacionamiento'),
              ),
            ),
          for (final r in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          'Reserva ${r['code']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        ReservationStatus('${r['status']}'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      money(r['amount']),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ingreso · ${lima(r['start_time'])}',
                      style: const TextStyle(color: appDashboardTextMuted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Salida · ${lima(r['end_time'])}',
                      style: const TextStyle(color: appDashboardTextMuted),
                    ),
                    if (r['status'] == 'PENDING_PAYMENT') ...[
                      const SizedBox(height: 20),
                      const Text(
                        'El espacio todavía no está confirmado. Revisa el pago pendiente.',
                        style: TextStyle(
                          fontSize: 12,
                          color: appDashboardTextMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: vm.busy ? null : () => payment(r),
                        child: const Text('Revisar y pagar'),
                      ),
                    ],
                    if ([
                      'PENDING_PAYMENT',
                      'CONFIRMED',
                      'ACTIVE',
                    ].contains(r['status'])) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: vm.busy ? null : () => cancel(r),
                        child: const Text('Cancelar reserva'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: vm.busy
                ? null
                : () async {
                    await vm.run(() async {
                      await widget.repository.resumeCommand();
                    });
                    if (vm.error == null) await refresh();
                  },
            icon: const Icon(Icons.sync_outlined, size: 20),
            label: const Text('Recuperar operación pendiente'),
          ),
        ],
      ),
    );
  }

  Future<void> cancel(Map<String, dynamic> r) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cancelar reserva?'),
        content: const Text(
          'Reembolso total con al menos 60 minutos de antelación. La cancelación tardía solo se permite si existe una política configurada. La devolución puede seguir pendiente después de cancelar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar cancelación'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await vm.run(() async {
      await widget.repository.command('cancel', {'reservationId': r['id']});
    });
    if (vm.error == null) await refresh();
  }

  Future<void> payment(Map<String, dynamic> r) async {
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) =>
          PaymentSheet(repository: widget.repository, reservation: r),
    );
    await refresh();
  }

  Future<void> editSpace([Map<String, dynamic>? space]) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PublicationScreen(
            repository: widget.repository,
            existing: space,
            latitude: vm.latitude,
            longitude: vm.longitude,
          ),
        ),
      );
  void accountRecords(ParkingRecordsKind kind) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ParkingRecordsScreen(
        repository: widget.repository,
        kind: kind,
        onEdit: editSpace,
      ),
    ),
  );
  Widget profile() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
    children: [
      const ParkingSectionTitle('Tu perfil'),
      const Align(
        alignment: Alignment.centerLeft,
        child: CircleAvatar(
          radius: 32,
          backgroundColor: appSurfaceSoft,
          child: Icon(Icons.person_outline_rounded, size: 32, color: appWhite),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        '${widget.repository.user?['name'] ?? ''}',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        '${widget.repository.user?['email'] ?? ''}',
        style: const TextStyle(color: appDashboardTextMuted, fontSize: 16),
      ),
      const SizedBox(height: 32),
      const Text(
        'CUENTA',
        style: TextStyle(
          color: appDashboardTextMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 16),
      profileRow(
        Icons.credit_card_outlined,
        'Historial de pagos',
        'Consulta tus transacciones',
        () => accountRecords(ParkingRecordsKind.payments),
      ),
      const SizedBox(height: 12),
      profileRow(
        Icons.notifications_none_rounded,
        'Avisos y preferencias',
        'Gestiona las actualizaciones de tus reservas',
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                NotificationPreferencesScreen(repository: widget.repository),
          ),
        ),
      ),
      const SizedBox(height: 12),
      profileRow(
        Icons.layers_outlined,
        'Aspecto del mapa',
        'Elige el estilo que mejor se adapte a ti',
        () => showMapThemePicker(context),
      ),
      const SizedBox(height: 12),
      profileRow(
        Icons.auto_awesome_outlined,
        'Copilot',
        'Asistencia para encontrar y reservar',
        openCopilot,
      ),
      if (widget.repository.isOwner) ...[
        const SizedBox(height: 32),
        const Text(
          'TUS ESTACIONAMIENTOS',
          style: TextStyle(
            color: appDashboardTextMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        profileRow(
          Icons.local_parking_outlined,
          'Mis publicaciones',
          'Publica y administra tus espacios',
          () => accountRecords(ParkingRecordsKind.spaces),
        ),
        const SizedBox(height: 12),
        profileRow(
          Icons.insights_outlined,
          'Agenda e ingresos',
          'Revisa tu actividad como propietario',
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  OwnerOverviewScreen(repository: widget.repository),
            ),
          ),
        ),
      ],
      const SizedBox(height: 40),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: logout,
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text('Cerrar sesión'),
      ),
    ],
  );
  Widget profileRow(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Material(
    color: appSurface,
    borderRadius: BorderRadius.circular(24),
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: appDashboardBorder),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: Icon(icon, size: 24, color: appWhite),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          style: const TextStyle(color: appDashboardTextMuted, fontSize: 12),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    ),
  );
  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Tus reservas y pagos seguirán disponibles cuando vuelvas a ingresar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(c).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.repository.logout();
  }
}

class BookingSheet extends StatefulWidget {
  const BookingSheet({
    required this.space,
    required this.repository,
    this.initialStart,
    this.initialEnd,
    super.key,
  });
  final ParkingSpace space;
  final ParkingRepository repository;
  final DateTime? initialStart, initialEnd;
  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  late DateTime start, end;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    start =
        widget.initialStart ??
        DateTime.now().toUtc().add(const Duration(hours: 2));
    end = widget.initialEnd ?? start.add(const Duration(hours: 1));
  }

  Future<void> pick(bool beginning) async {
    final current = (beginning ? start : end).subtract(
      const Duration(hours: 5),
    );
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time == null || !mounted) return;
    final date = DateTime.utc(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).add(const Duration(hours: 5));
    setState(() {
      if (beginning) {
        start = date;
        if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));
      } else {
        end = date;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final amount =
        (widget.space.hourlyRate *
                end.difference(start).inMilliseconds /
                3600000)
            .ceil();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.space.title,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                tooltip: 'Cerrar reserva',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.space.address,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${money(widget.space.hourlyRate)} / hora',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: busy ? null : () => pick(true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ingreso: ${lima(start.toIso8601String())}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: busy ? null : () => pick(false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Salida: ${lima(end.toIso8601String())}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Total estimado: ${money(amount > 0 ? amount : 0)}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Retención máxima: 10 minutos. Reembolso total si cancelas con al menos 60 minutos de antelación. Sin política tardía configurada, la cancelación tardía no está habilitada.',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (error != null) ParkingNotice(error!),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!start.isAfter(DateTime.now()) ||
                        !end.isAfter(start) ||
                        amount <= 0) {
                      setState(
                        () => error =
                            'Elige un ingreso futuro y una salida posterior al ingreso.',
                      );
                      return;
                    }
                    HapticFeedback.lightImpact();
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final hold = await widget.repository.command('hold', {
                        'spaceId': widget.space.id,
                        'start': start.toIso8601String(),
                        'end': end.toIso8601String(),
                        'expectedAmount': amount,
                        'supplyRevision': widget.space.revision,
                      });
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Confirmar pago')),
                            body: SafeArea(
                              top: false,
                              child: PaymentSheet(
                                repository: widget.repository,
                                reservation: hold,
                                space: widget.space,
                              ),
                            ),
                          ),
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } on ParkingApiException catch (e) {
                      if (mounted) {
                        setState(() => error = parkingActionError(e));
                      }
                    } on Object {
                      if (mounted) {
                        setState(
                          () => error =
                              'No pudimos verificar el espacio. Revisa tu conexión y consulta tus reservas antes de reintentar.',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(
              busy ? 'Validando disponibilidad…' : 'Continuar con la reserva',
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    required this.repository,
    required this.reservation,
    this.space,
    super.key,
  });
  final ParkingRepository repository;
  final Map<String, dynamic> reservation;
  final ParkingSpace? space;
  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late Map<String, dynamic> reservation = widget.reservation;
  bool busy = false;
  String? message;
  @override
  Widget build(BuildContext context) => reservation['status'] == 'CONFIRMED'
      ? _confirmed(context)
      : SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reserva ${reservation['code']}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${money(reservation['amount'])} · PEN',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text('Estado: ${parkingStatus('${reservation['status']}')}'),
              const SizedBox(height: 12),
              Text('Retención hasta ${lima(reservation['expires_at'])}'),
              const SizedBox(height: 24),
              const Text(
                'Entorno local: pagos sandbox, sin movimiento de dinero real. Si el servidor usa Mercado Pago, se abrirá el checkout del proveedor.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 24),
              if (message != null) ParkingNotice(message!),
              FilledButton(
                onPressed: busy || reservation['status'] != 'PENDING_PAYMENT'
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        setState(() {
                          busy = true;
                          message =
                              'Pago en proceso. Todavía no es una reserva confirmada.';
                        });
                        try {
                          await widget.repository.command('confirm', {
                            'reservationId': reservation['id'],
                            'sandboxResult': 'approved',
                          });
                          for (var i = 0; i < 15; i++) {
                            await Future<void>.delayed(
                              const Duration(seconds: 1),
                            );
                            if (!mounted) return;
                            final current =
                                await widget.repository.request(
                                      'GET',
                                      '/reservations/${reservation['id']}',
                                    )
                                    as Map<String, dynamic>;
                            if (!mounted) return;
                            setState(() => reservation = current);
                            if (current['status'] != 'PENDING_PAYMENT') break;
                            final payments = await widget.repository.list(
                              '/payments/mine',
                            );
                            final matching = payments
                                .where(
                                  (p) => p['reservation_id'] == current['id'],
                                )
                                .toList();
                            if (matching.isNotEmpty &&
                                matching.first['checkout_url'] != null) {
                              await launchUrl(
                                Uri.parse(
                                  matching.first['checkout_url'] as String,
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                              break;
                            }
                            if (matching.isNotEmpty &&
                                matching.first['status'] == 'REJECTED') {
                              break;
                            }
                          }
                          if (mounted) {
                            setState(
                              () =>
                                  message = reservation['status'] == 'CONFIRMED'
                                  ? 'Reserva confirmada por el servidor.'
                                  : 'El pago no ha confirmado la reserva. Consulta su estado antes de reintentar.',
                            );
                          }
                        } on ParkingApiException catch (e) {
                          if (mounted) {
                            setState(() => message = parkingActionError(e));
                          }
                        } on Object {
                          if (mounted) {
                            setState(
                              () => message =
                                  'No pudimos consultar el resultado. Revisa el estado de tu reserva antes de iniciar otro pago.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: Text(
                  busy ? 'Consultando resultado…' : 'Confirmar e iniciar pago',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          final r =
                              await widget.repository.request(
                                    'GET',
                                    '/reservations/${reservation['id']}',
                                  )
                                  as Map<String, dynamic>;
                          if (mounted) {
                            setState(() {
                              reservation = r;
                              message = 'Estado actualizado.';
                            });
                          }
                        } on Object {
                          if (mounted) {
                            setState(
                              () => message =
                                  'No pudimos actualizar la reserva. Inténtalo de nuevo.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Consultar estado'),
              ),
            ],
          ),
        );

  Widget _confirmed(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      begin: MediaQuery.disableAnimationsOf(context) ? 0 : 1,
      end: 0,
    ),
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) =>
        Transform.translate(offset: Offset(0, value * 240), child: child),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFF29A869),
              child: Icon(Icons.check_rounded, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'Reserva confirmada',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Reserva ${reservation['code']} · ${money(reservation['amount'])}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (widget.space != null)
              FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.https('www.google.com', '/maps/dir/', {
                    'api': '1',
                    'destination':
                        '${widget.space!.latitude},${widget.space!.longitude}',
                  }),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Cómo llegar'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    ),
  );
}

class PublicationScreen extends StatefulWidget {
  const PublicationScreen({
    required this.repository,
    required this.latitude,
    required this.longitude,
    this.existing,
    super.key,
  });
  final ParkingRepository repository;
  final Map<String, dynamic>? existing;
  final double latitude, longitude;
  @override
  State<PublicationScreen> createState() => _PublicationScreenState();
}

class _PublicationScreenState extends State<PublicationScreen> {
  final fields = <String, TextEditingController>{};
  bool active = true, busy = false;
  String? error;
  final features = <String>{};
  late DateTime start, end;
  @override
  void initState() {
    super.initState();
    final b = widget.existing?['body'] as Map<String, dynamic>? ?? {};
    for (final key in [
      'title',
      'address',
      'description',
      'photoUrl',
      'latitude',
      'longitude',
      'hourlyRate',
      'widthCm',
      'lengthCm',
      'accessInstructions',
    ]) {
      fields[key] = TextEditingController(
        text:
            '${b[key] ?? (key == 'latitude'
                    ? widget.latitude
                    : key == 'longitude'
                    ? widget.longitude
                    : '')}',
      );
    }
    if (b['hourlyRate'] != null) {
      fields['hourlyRate']!.text = '${(b['hourlyRate'] as num) / 100}';
    }
    active = b['active'] as bool? ?? true;
    features.addAll(List<String>.from(b['features'] as List? ?? []));
    final windows = b['windows'] as List?;
    start = windows?.isNotEmpty == true
        ? DateTime.parse(windows!.first['start'] as String)
        : DateTime.now().toUtc();
    end = windows?.isNotEmpty == true
        ? DateTime.parse(windows!.first['end'] as String)
        : start.add(const Duration(days: 30));
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null ? 'Publicar espacio' : 'Editar espacio',
      ),
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(24),
        children: [
          for (final entry in <String, String>{
            'title': 'Título',
            'address': 'Dirección',
            'description': 'Descripción',
            'photoUrl': 'Foto del estacionamiento',
            'latitude': 'Latitud',
            'longitude': 'Longitud',
            'hourlyRate': 'Precio por hora (S/)',
            'widthCm': 'Ancho (cm)',
            'lengthCm': 'Largo (cm)',
            'accessInstructions': 'Condiciones de acceso',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                enabled: !busy,
                controller: fields[entry.key],
                decoration: InputDecoration(
                  labelText: entry.value,
                  helperText: entry.key == 'photoUrl'
                      ? 'Enlace HTTPS a una foto real. Opcional.'
                      : null,
                ),
                keyboardType: entry.key == 'photoUrl'
                    ? TextInputType.url
                    : [
                        'latitude',
                        'longitude',
                        'hourlyRate',
                        'widthCm',
                        'lengthCm',
                      ].contains(entry.key)
                    ? const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      )
                    : TextInputType.text,
              ),
            ),
          SwitchListTile(
            title: const Text('Publicación activa'),
            value: active,
            onChanged: busy ? null : (v) => setState(() => active = v),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final feature in ['covered', 'security', 'ev', 'accessible'])
                FilterChip(
                  label: Text(switch (feature) {
                    'covered' => 'Techado',
                    'security' => 'Seguridad',
                    'ev' => 'Carga eléctrica',
                    'accessible' => 'Accesible',
                    _ => feature,
                  }),
                  selected: features.contains(feature),
                  onSelected: busy
                      ? null
                      : (v) => setState(() {
                          if (v) {
                            features.add(feature);
                          } else {
                            features.remove(feature);
                          }
                        }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Ventana disponible: ${lima(start.toIso8601String())} — ${lima(end.toIso8601String())}',
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (range != null && mounted) {
                      setState(() {
                        start = DateTime.utc(
                          range.start.year,
                          range.start.month,
                          range.start.day,
                          5,
                        );
                        end = DateTime.utc(
                          range.end.year,
                          range.end.month,
                          range.end.day,
                          5,
                        ).add(const Duration(days: 1));
                      });
                    }
                  },
            child: const Text('Cambiar días disponibles (hora de Lima)'),
          ),
          const SizedBox(height: 16),
          const Text(
            'La modificación se valida antes de aparecer en búsquedas. No elimina las reservas existentes. Cada publicación representa una plaza.',
          ),
          const SizedBox(height: 24),
          if (error != null) ParkingNotice(error!),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final photo = fields['photoUrl']!.text.trim();
                      final uri = Uri.tryParse(photo);
                      if (photo.isNotEmpty &&
                          (uri?.scheme != 'https' ||
                              uri!.host.isEmpty ||
                              photo.length > 2048)) {
                        setState(
                          () => error =
                              'La fotografía debe tener una dirección HTTPS válida.',
                        );
                        return;
                      }
                      final body = <String, dynamic>{
                        for (final key in [
                          'title',
                          'address',
                          'description',
                          'accessInstructions',
                        ])
                          key: fields[key]!.text.trim(),
                        'latitude': double.parse(fields['latitude']!.text),
                        'longitude': double.parse(fields['longitude']!.text),
                        'hourlyRate':
                            (double.parse(fields['hourlyRate']!.text) * 100)
                                .round(),
                        'widthCm': int.parse(fields['widthCm']!.text),
                        'lengthCm': int.parse(fields['lengthCm']!.text),
                        'active': active,
                        'features': features.toList(),
                        'windows': [
                          {
                            'start': start.toUtc().toIso8601String(),
                            'end': end.toUtc().toIso8601String(),
                          },
                        ],
                      };
                      if (photo.isNotEmpty) body['photoUrl'] = photo;
                      await widget.repository.request(
                        widget.existing == null ? 'POST' : 'PUT',
                        widget.existing == null
                            ? '/spaces'
                            : '/spaces/${widget.existing!['id']}',
                        body: widget.existing == null
                            ? body
                            : {
                                'revision': widget.existing!['revision'],
                                'space': body,
                              },
                      );
                      if (context.mounted) Navigator.pop(context);
                    } on Object {
                      if (mounted) {
                        setState(
                          () => error =
                              'No pudimos guardar la publicación. Revisa los datos y tu conexión antes de volver a intentarlo.',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? 'Enviando revisión…' : 'Guardar publicación'),
          ),
        ],
      ),
    ),
  );
}

String parkingActionError(ParkingApiException error) {
  final message = error.message.toLowerCase();
  if (message.contains('interval') ||
      message.contains('available') ||
      message.contains('revision')) {
    return 'El espacio o su disponibilidad cambiaron. Actualiza la búsqueda y elige otro horario.';
  }
  if (message.contains('pending') ||
      message.contains('pendiente') ||
      message.contains('proceso')) {
    return 'Hay una operación pendiente. Consulta tus reservas antes de continuar.';
  }
  if (message.contains('expired') || message.contains('expir')) {
    return 'La retención venció. Consulta tus reservas antes de iniciar otra.';
  }
  return 'No pudimos completar la operación. Revisa el estado de tu reserva antes de reintentar.';
}
