import 'package:flutter/material.dart';

import '../../../../core/app_theme.dart';

/// Resumen de una unidad tocada en el mapa: quién la maneja y qué auto es.
///
/// El marcador ya llevaba todos estos datos apilados en su etiqueta de
/// accesibilidad, donde solo los oía un lector de pantalla. Al tocar la unidad
/// ahora se ven.
class MapUnitSummary {
  const MapUnitSummary({
    required this.driverName,
    required this.estado,
    this.plate,
    this.vehicleModel,
    this.serviceCode,
    this.phone,
    this.tiempoDeLlegada,
  });

  final String driverName;

  /// Qué está haciendo: en servicio, disponible, sin conexión.
  final String estado;
  final String? plate;
  final String? vehicleModel;
  final String? serviceCode;
  final String? phone;

  /// Cuánto falta para llegar al destino, si corresponde calcularlo.
  ///
  /// Llega como futuro y no como valor porque la consulta a Google tarda: la
  /// ficha abre de inmediato con lo que ya se sabe y completa el tiempo cuando
  /// llega. `null` significa que no se pidió —observador, unidad sin servicio
  /// en curso o sin destino conocido— y entonces no se muestra nada.
  final Future<Duration?>? tiempoDeLlegada;
}

Future<void> showMapUnitSheet(BuildContext context, MapUnitSummary unidad) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _MapUnitSheet(unidad: unidad),
  );
}

class _MapUnitSheet extends StatelessWidget {
  const _MapUnitSheet({required this.unidad});

  final MapUnitSummary unidad;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: appSurface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              unidad.driverName,
              style: texto.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(unidad.estado, style: texto.bodyMedium?.copyWith(color: appLime)),
            const SizedBox(height: 18),
            _Dato(etiqueta: 'Vehículo', valor: _vehiculo()),
            if (unidad.tiempoDeLlegada != null)
              _TiempoDeLlegada(futuro: unidad.tiempoDeLlegada!),
            if (unidad.serviceCode != null)
              _Dato(etiqueta: 'Servicio', valor: unidad.serviceCode!),
            if (unidad.phone != null && unidad.phone!.isNotEmpty)
              _Dato(etiqueta: 'Teléfono', valor: unidad.phone!),
          ],
        ),
      ),
    );
  }

  String _vehiculo() {
    final placa = unidad.plate;
    final modelo = unidad.vehicleModel;
    if (placa == null && modelo == null) return 'sin vehículo vinculado';
    if (modelo == null) return placa!;
    if (placa == null) return modelo;
    return '$placa · $modelo';
  }

}

/// Fila del tiempo restante: se completa cuando Google contesta.
///
/// Si no hay estimación no deja un hueco ni un guion: la fila desaparece. Ese
/// silencio es deliberado, porque un tiempo equivocado se toma por bueno.
class _TiempoDeLlegada extends StatelessWidget {
  const _TiempoDeLlegada({required this.futuro});

  final Future<Duration?> futuro;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Duration?>(
      future: futuro,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Dato(etiqueta: 'Llega en', valor: 'calculando…');
        }
        final falta = snapshot.data;
        if (falta == null) return const SizedBox.shrink();
        return _Dato(etiqueta: 'Llega en', valor: _formatear(falta), destacado: true);
      },
    );
  }

  static String _formatear(Duration falta) {
    final minutos = falta.inSeconds <= 60 ? 1 : (falta.inSeconds / 60).ceil();
    if (minutos < 60) return '$minutos min';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    return resto == 0 ? '$horas h' : '$horas h ${resto.toString().padLeft(2, '0')} min';
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;

  /// Resalta el dato que motivó abrir la ficha, para leerlo de un vistazo.
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              etiqueta,
              style: texto.bodySmall?.copyWith(color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: texto.bodyMedium?.copyWith(
                fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                color: destacado ? appLime : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
