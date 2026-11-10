import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/date_formats.dart';
import '../view_models/service_summary_view_model.dart';

class ServiceSummaryScreen extends StatefulWidget {
  const ServiceSummaryScreen({required this.serviceId, super.key});

  final String serviceId;

  @override
  State<ServiceSummaryScreen> createState() => _ServiceSummaryScreenState();
}

class _ServiceSummaryScreenState extends State<ServiceSummaryScreen> {
  late final ServiceSummaryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ServiceSummaryViewModel(
      serviceId: widget.serviceId,
      serviceRepository: AppScope.of(context, listen: false).serviceRepository,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen del servicio')),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          final summary = _viewModel.summary;
          if (_viewModel.loading && summary == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_viewModel.error != null && summary == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_viewModel.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _viewModel.load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (summary == null) return const SizedBox.shrink();
          return RefreshIndicator(
            onRefresh: _viewModel.load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _StatusCard(status: summary.status),
                const SizedBox(height: 16),
                _MetricGrid(
                  values: [
                    ('Inicio', _date(summary.startedAt)),
                    ('Fin', _date(summary.finishedAt)),
                    ('Duración', _duration(summary.durationSeconds)),
                    ('Distancia', _distance(summary.distanceMeters)),
                    ('Paradas', '${summary.stopCount}'),
                    ('Incidencias', '${summary.incidentCount}'),
                    ('Vel. media', _speed(summary.averageSpeedMps)),
                    ('Vel. máxima', _speed(summary.maximumSpeedMps)),
                  ],
                ),
                if (summary.status != 'READY') ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Las métricas pueden cambiar mientras el backend reconcilia posiciones pendientes.',
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _date(DateTime? value) => value == null
      ? 'Pendiente'
      : formatDateTime(value, includeYear: true, separator: ' ');

  String _duration(int? seconds) {
    if (seconds == null) return 'Pendiente';
    final duration = Duration(seconds: seconds);
    return '${duration.inHours} h ${duration.inMinutes.remainder(60)} min';
  }

  String _distance(double? meters) =>
      meters == null ? 'Pendiente' : '${(meters / 1000).toStringAsFixed(1)} km';

  String _speed(double? metersPerSecond) => metersPerSecond == null
      ? 'Pendiente'
      : '${(metersPerSecond * 3.6).toStringAsFixed(1)} km/h';
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(status == 'READY' ? Icons.task_alt : Icons.sync_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status == 'READY'
                    ? 'Resumen listo'
                    : status == 'FAILED'
                    ? 'No se pudo generar el resumen'
                    : 'Resumen en procesamiento',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.values});

  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value.$1),
                        const SizedBox(height: 5),
                        Text(
                          value.$2,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
