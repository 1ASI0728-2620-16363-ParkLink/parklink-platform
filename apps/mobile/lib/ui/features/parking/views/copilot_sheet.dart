import 'package:flutter/material.dart';
import '../../../../domain/models/parking_space.dart';
import '../../../core/app_theme.dart';
import '../view_models/copilot_view_model.dart';

String _money(Object? cents) =>
    'S/ ${(num.parse('$cents') / 100).toStringAsFixed(2)}';
String _time(Object? value) {
  final d = DateTime.parse('$value').toUtc().subtract(const Duration(hours: 5));
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)} · Lima';
}

class CopilotSheet extends StatefulWidget {
  const CopilotSheet({required this.viewModel, super.key});
  final CopilotViewModel viewModel;
  @override
  State<CopilotSheet> createState() => _CopilotSheetState();
}

class _CopilotSheetState extends State<CopilotSheet> {
  final input = TextEditingController(), scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    widget.viewModel.loadStatus();
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send([String? text]) async {
    final message = text ?? input.text;
    if (message.trim().isEmpty || widget.viewModel.busy) return;
    input.clear();
    FocusScope.of(context).unfocus();
    await widget.viewModel.send(message);
    if (mounted && scroll.hasClients) {
      await scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<DateTime?> pick(DateTime initial) async {
    final lima = initial.toUtc().subtract(const Duration(hours: 5));
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(lima.year, lima.month, lima.day),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: lima.hour, minute: lima.minute),
    );
    if (time == null) return null;
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).add(const Duration(hours: 5));
  }

  Future<void> chooseInterval() async {
    final start = await pick(
      widget.viewModel.start ??
          DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    if (start == null || !mounted) return;
    final end = await pick(
      widget.viewModel.end ?? start.add(const Duration(hours: 1)),
    );
    if (end == null || !mounted) return;
    if (!end.isAfter(start) || !start.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Elige un horario futuro con salida posterior al ingreso.',
          ),
        ),
      );
      return;
    }
    widget.viewModel.interval(start, end);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      return SizedBox(
        height:
            (MediaQuery.sizeOf(context).height * .88 -
                    MediaQuery.viewInsetsOf(context).bottom)
                .clamp(180.0, MediaQuery.sizeOf(context).height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: appBlack),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Copilot',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Cerrar asistente',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  vm.status == null
                      ? 'Verificando conexión…'
                      : vm.status!['runtimeReady'] == true &&
                            vm.status!['inferenceEnabled'] == true
                      ? 'OpenCode preparado · proveedor sujeto a disponibilidad'
                      : 'OpenCode no disponible en este momento',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: vm.busy ? null : chooseInterval,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        vm.start == null
                            ? 'Elegir horario de reserva'
                            : '${_time(vm.start!.toIso8601String())}\n${_time(vm.end!.toIso8601String())}',
                      ),
                    ),
                  ),
                  if (vm.start != null)
                    IconButton(
                      onPressed: vm.busy ? null : () => vm.interval(null, null),
                      tooltip: 'Quitar horario',
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (vm.entries.isEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Hola. Te ayudo a comparar espacios y preparar tu reserva. Antes de cualquier cambio, tú confirmas el importe y las condiciones.',
                        ),
                      ),
                      for (final text in [
                        'Busca el estacionamiento más cercano',
                        'Busca el estacionamiento más barato',
                        'Reserva el lugar más barato',
                        'Muéstrame mis reservas',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            onPressed: vm.busy ? null : () => send(text),
                            child: Text(text),
                          ),
                        ),
                      const Text(
                        'Se utiliza el centro de tu mapa como referencia. Los pagos locales son sandbox y no mueven dinero real.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                    for (final entry in vm.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Align(
                          alignment: entry.user
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: entry.user ? null : double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: entry.user
                                  ? const Color(0xFFD7FCF7)
                                  : const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.text,
                                  style: const TextStyle(color: appBlack),
                                ),
                                if (entry.data?['warning'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '${entry.data!['warning']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF555555),
                                      ),
                                    ),
                                  ),
                                if (entry.data?['engine'] == 'opencode')
                                  const Text(
                                    'Interpretado por OpenCode',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                for (final item
                                    in entry.data?['items'] as List? ?? [])
                                  space(item as Map<String, dynamic>),
                                for (final item
                                    in entry.data?['reservations'] as List? ??
                                        [])
                                  reservation(item as Map<String, dynamic>),
                                if (entry.data?['proposal'] != null)
                                  proposal(
                                    entry.data!['proposal']
                                        as Map<String, dynamic>,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (vm.busy)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text('Consultando el estado real…'),
                            ),
                          ],
                        ),
                      ),
                    if (vm.error != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text(vm.error!),
                              TextButton(
                                onPressed: vm.busy ? null : vm.retry,
                                child: const Text(
                                  'Reintentar el mismo mensaje',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          enabled: !vm.busy,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1500,
                          decoration: const InputDecoration(
                            labelText: 'Pide ayuda para estacionar',
                            counterText: '',
                          ),
                          onSubmitted: (_) => send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: vm.busy ? null : send,
                        tooltip: 'Enviar mensaje',
                        style: IconButton.styleFrom(
                          backgroundColor: appLime,
                          foregroundColor: appBlack,
                          minimumSize: const Size(52, 52),
                        ),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget space(Map<String, dynamic> item) {
    final body = item['body'] as Map<String, dynamic>;
    final photo = Uri.tryParse('${body['photoUrl'] ?? ''}');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo != null && photo.scheme == 'https' && photo.host.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                photo.toString(),
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Text(
            '${body['title']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('${body['address']}'),
          if (body['description'] is String && (body['description'] as String).isNotEmpty)
            Text(body['description'] as String),
          Text(
            '${_money(body['hourlyRate'])} / hora · ${(item['distance_m'] as num).round()} m',
          ),
          TextButton(
            onPressed: widget.viewModel.busy
                ? null
                : () => Navigator.pop(context, ParkingSpace.fromJson(item)),
            child: const Text('Revisar espacio'),
          ),
        ],
      ),
    );
  }

  Widget reservation(Map<String, dynamic> item) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reserva ${item['code']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text('${item['status']} · ${_money(item['amount'])}'),
        Text('${_time(item['start_time'])}\n${_time(item['end_time'])}'),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: widget.viewModel.busy
                  ? null
                  : () => widget.viewModel.refreshReservation('${item['id']}'),
              child: const Text('Actualizar estado'),
            ),
            if (item['status'] == 'PENDING_PAYMENT')
              TextButton(
                onPressed: widget.viewModel.busy
                    ? null
                    : () => widget.viewModel.propose('pay', '${item['id']}'),
                child: const Text('Revisar pago'),
              ),
            if ([
              'PENDING_PAYMENT',
              'CONFIRMED',
              'ACTIVE',
            ].contains(item['status']))
              TextButton(
                onPressed: widget.viewModel.busy
                    ? null
                    : () => widget.viewModel.propose('cancel', '${item['id']}'),
                child: const Text('Revisar cancelación'),
              ),
          ],
        ),
      ],
    ),
  );
  Widget proposal(Map<String, dynamic> item) {
    final summary = item['summary'] as Map<String, dynamic>,
        id = '${item['confirmationId']}';
    final done = widget.viewModel.completedConfirmations.contains(id);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          Text(
            '${summary['title']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (summary['address'] != null) Text('${summary['address']}'),
          if (summary['start'] != null)
            Text('${_time(summary['start'])}\n${_time(summary['end'])}'),
          Text(
            'Importe: ${_money(summary['amount'])} · PEN',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text('${summary['policy']}'),
          const Text(
            'La autorización vence en 5 minutos. No confirmes si el resumen no coincide con lo que necesitas.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.viewModel.busy || done
                ? null
                : () => widget.viewModel.confirm(id, waitForPayment: summary['action'] == 'hold_and_pay'),
            child: Text(
              done
                  ? 'Operación procesada'
                  : switch (summary['action']) {
                      'pay' => 'Confirmar e iniciar pago',
                      'hold_and_pay' => 'Pagar y reservar',
                      'cancel' => 'Confirmar cancelación',
                      _ => 'Confirmar retención (sin cobro)',
                    },
            ),
          ),
        ],
      ),
    );
  }
}
