import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../data/repositories/parking_repository.dart';
import '../../../core/app_theme.dart';
import 'parking_widgets.dart';

String _date(Object? raw) {
  final value = DateTime.tryParse(
    '$raw',
  )?.toUtc().subtract(const Duration(hours: 5));
  if (value == null) return 'Fecha no disponible';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} (Lima)';
}

String parkingStatus(String status) => switch (status) {
  'PENDING_PAYMENT' => 'Pago pendiente',
  'CONFIRMED' => 'Confirmada',
  'ACTIVE' => 'En curso',
  'COMPLETED' => 'Completada',
  'CANCELLED' => 'Cancelada',
  'EXPIRED' => 'Vencida',
  'AUTHORIZED' => 'Autorizado',
  'REFUNDED' => 'Reembolsado',
  'REJECTED' => 'Rechazado',
  'PUBLISHED' => 'Publicado',
  'REVIEWING' => 'En revisión',
  'CREATED' => 'En proceso',
  'REFUND_PENDING' => 'Reembolso pendiente',
  'PARTIALLY_REFUNDED' => 'Reembolso parcial',
  _ => 'En proceso',
};

class ReservationStatus extends StatelessWidget {
  const ReservationStatus(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: appSurfaceSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: appDashboardBorder),
    ),
    child: Text(
      parkingStatus(status),
      style: const TextStyle(
        color: appWhite,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

enum ParkingRecordsKind { payments, notifications, spaces }

/// Secondary account destinations keep their own requests and do not overwrite
/// reservation tab state while the user edits a publication or reads a notice.
class ParkingRecordsScreen extends StatefulWidget {
  const ParkingRecordsScreen({
    required this.repository,
    required this.kind,
    this.onEdit,
    super.key,
  });
  final ParkingRepository repository;
  final ParkingRecordsKind kind;
  final Future<void> Function([Map<String, dynamic>? space])? onEdit;
  @override
  State<ParkingRecordsScreen> createState() => _ParkingRecordsScreenState();
}

class _ParkingRecordsScreenState extends State<ParkingRecordsScreen> {
  List<Map<String, dynamic>> rows = [];
  bool busy = true;
  String? error;
  String get title => switch (widget.kind) {
    ParkingRecordsKind.payments => 'Historial de pagos',
    ParkingRecordsKind.notifications => 'Tus avisos',
    ParkingRecordsKind.spaces => 'Mis publicaciones',
  };
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        busy = true;
        error = null;
      });
    }
    try {
      final data = await widget.repository.list(switch (widget.kind) {
        ParkingRecordsKind.payments => '/payments/mine',
        ParkingRecordsKind.notifications => '/notifications',
        ParkingRecordsKind.spaces => '/spaces/mine',
      });
      if (mounted) setState(() => rows = data);
    } on Object {
      if (mounted) {
        setState(
          () => error =
              'No pudimos cargar la información. Revisa tu conexión e inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    await widget.onEdit?.call(row);
    if (mounted) await load();
  }

  Future<void> read(Map<String, dynamic> row) async {
    try {
      await widget.repository.request(
        'PUT',
        '/notifications/${row['id']}/read',
      );
      if (mounted) await load();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos actualizar el aviso. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.kind == ParkingRecordsKind.spaces) ...[
              FilledButton.icon(
                onPressed: busy ? null : edit,
                icon: const Icon(Icons.add),
                label: const Text('Publicar estacionamiento'),
              ),
              const SizedBox(height: 24),
            ],
            if (error != null) ParkingNotice(error!, onRetry: load),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (!busy && error == null && rows.isEmpty)
              ParkingEmptyState(
                icon: switch (widget.kind) {
                  ParkingRecordsKind.payments => Icons.credit_card_outlined,
                  ParkingRecordsKind.notifications => Icons.notifications_none,
                  ParkingRecordsKind.spaces => Icons.local_parking_outlined,
                },
                title: switch (widget.kind) {
                  ParkingRecordsKind.payments => 'Todavía no hay pagos',
                  ParkingRecordsKind.notifications => 'Estás al día',
                  ParkingRecordsKind.spaces => 'Publica tu primer espacio',
                },
                message: switch (widget.kind) {
                  ParkingRecordsKind.payments =>
                    'Aquí aparecerán tus transacciones y reembolsos.',
                  ParkingRecordsKind.notifications =>
                    'Aquí aparecerán las actualizaciones de tus reservas.',
                  ParkingRecordsKind.spaces =>
                    'Añade los datos y una fotografía real de tu estacionamiento.',
                },
              ),
            if (!busy)
              for (final row in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: record(row),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
  Widget record(Map<String, dynamic> row) {
    if (widget.kind == ParkingRecordsKind.spaces) {
      final body = row['body'] as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${body['title']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${body['address']}',
            style: const TextStyle(color: appDashboardTextMuted),
          ),
          const SizedBox(height: 16),
          Text('${parkingMoney(body['hourlyRate'])} / hora'),
          const SizedBox(height: 8),
          Text(parkingStatus('${row['state']}')),
          if (row['rejection'] != null) ...[
            const SizedBox(height: 8),
            const Text(
              'La revisión necesita ajustes. Revisa los datos y vuelve a enviar la publicación.',
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => edit(row),
            child: const Text('Editar publicación'),
          ),
        ],
      );
    }
    if (widget.kind == ParkingRecordsKind.notifications) {
      final body = row['body'] as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reserva ${body['code'] ?? ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(parkingStatus('${body['status']}')),
          const SizedBox(height: 12),
          Text(
            _date(row['created_at']),
            style: const TextStyle(color: appDashboardTextMuted, fontSize: 12),
          ),
          if (row['read_at'] == null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => read(row),
              child: const Text('Marcar como leído'),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parkingMoney(row['amount']),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(parkingStatus('${row['status']}')),
        const SizedBox(height: 16),
        Text(
          _date(row['created_at']),
          style: const TextStyle(color: appDashboardTextMuted),
        ),
        if (row['provider'] == 'sandbox') ...[
          const SizedBox(height: 8),
          const Text(
            'Pago de prueba · sin movimiento de dinero real',
            style: TextStyle(fontSize: 12, color: appDashboardTextMuted),
          ),
        ],
      ],
    );
  }
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({required this.repository, super.key});
  final ParkingRepository repository;
  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool? enabled;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data =
          await widget.repository.request('GET', '/notifications/preferences')
              as Map;
      if (mounted) setState(() => enabled = data['in_app'] == true);
    } on Object {
      if (mounted) {
        setState(() => error = 'No pudimos consultar tus preferencias.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(bool value) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.request(
        'PUT',
        '/notifications/preferences',
        body: {'inApp': value},
      );
      if (mounted) setState(() => enabled = value);
    } on Object {
      if (mounted) {
        setState(() => error = 'No se guardó el cambio. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avisos y preferencias')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const ParkingSectionTitle(
            'A tu manera',
            subtitle:
                'Decide cómo recibir las actualizaciones de tus reservas.',
          ),
          if (error != null) ParkingNotice(error!, onRetry: load),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            tileColor: appSurface,
            title: const Text('Avisos en la aplicación'),
            subtitle: const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Confirmaciones, pagos y cambios de estado.',
                style: TextStyle(color: appDashboardTextMuted),
              ),
            ),
            value: enabled ?? false,
            onChanged: busy || enabled == null ? null : save,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ParkingRecordsScreen(
                  repository: widget.repository,
                  kind: ParkingRecordsKind.notifications,
                ),
              ),
            ),
            icon: const Icon(Icons.notifications_none),
            label: const Text('Consultar avisos'),
          ),
        ],
      ),
    ),
  );
}

class OwnerOverviewScreen extends StatefulWidget {
  const OwnerOverviewScreen({required this.repository, super.key});
  final ParkingRepository repository;
  @override
  State<OwnerOverviewScreen> createState() => _OwnerOverviewScreenState();
}

class _OwnerOverviewScreenState extends State<OwnerOverviewScreen> {
  Map<String, dynamic>? data;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result =
          await widget.repository.request('GET', '/owner/dashboard')
              as Map<String, dynamic>;
      if (mounted) setState(() => data = result);
    } on Object {
      if (mounted) setState(() => error = 'No pudimos consultar tu actividad.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda e ingresos')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (error != null) ParkingNotice(error!, onRetry: load),
              if (d != null && !busy) ...[
                const Text(
                  'INGRESOS NETOS',
                  style: TextStyle(color: appDashboardTextMuted),
                ),
                const SizedBox(height: 12),
                Text(
                  parkingMoney(d['income']),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                Text(
                  'Espacios: ${(d['spaces'] as Map)['total']} · Activos: ${(d['spaces'] as Map)['active']} · Ocupados: ${d['occupiedSpaces']}',
                ),
                const SizedBox(height: 16),
                Text(
                  'Pendientes: ${(d['reservations'] as Map)['pending']} · Activas: ${(d['reservations'] as Map)['active']} · Completadas: ${(d['reservations'] as Map)['completed']}',
                ),
                const SizedBox(height: 32),
                Text(
                  'Ingresos por mes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                for (final entry in (d['byMonth'] as Map).entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${entry.key}'),
                    trailing: Text(parkingMoney(entry.value)),
                  ),
                const SizedBox(height: 32),
                Text(
                  'Próximas reservas',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                for (final r in d['upcoming'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Reserva ${r['code']}'),
                    subtitle: Text(_date(r['start_time'])),
                  ),
                const SizedBox(height: 32),
                Text(
                  'Transacciones',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                for (final p in d['transactions'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${parkingMoney(p['amount'])} · ${parkingStatus('${p['status']}')}',
                    ),
                    subtitle: Text(
                      'Devuelto: ${parkingMoney(p['refunded_amount'])}',
                    ),
                  ),
                if (d['truncated'] == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text(
                      'Vista limitada a las últimas 500 operaciones; no es un balance contable completo.',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
