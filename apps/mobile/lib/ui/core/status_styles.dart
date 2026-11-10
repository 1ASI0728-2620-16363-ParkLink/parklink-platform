import 'package:flutter/material.dart';

import 'app_theme.dart';

String statusLabel(String status) {
  final normalized = status
      .trim()
      .toUpperCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return switch (normalized) {
    'BUSCANDO_CONDUCTOR' || 'SEARCHING' => 'Buscando conductor',
    // Los tres estados vivos, más la suspensión del admin.
    'PENDIENTE' => 'Pendiente',
    'EN_SERVICIO' => 'En servicio',
    // Lo que sigue ya no se asigna nunca, pero aparece en la bitácora de los
    // servicios anteriores al modelo de tres estados.
    'ASIGNADO' => 'Asignado',
    'PROGRAMADO' => 'Programado',
    'PENDIENTE_INICIO' => 'Pendiente de inicio',
    'EN_CAMINO_AL_ORIGEN' => 'Hacia el origen',
    'EN_RUTA_ORIGEN' => 'Hacia el origen',
    'EN_PUNTO_ORIGEN' => 'En el origen',
    'INICIADO' => 'Iniciado',
    'EN_RUTA' => 'En ruta',
    'EN_RECORRIDO' => 'En recorrido',
    'EN_PARADA' => 'En parada',
    'REANUDADO' => 'Reanudado',
    'EN_DESTINO' => 'En destino',
    'FINALIZADO' => 'Finalizado',
    'CANCELADO' => 'Cancelado',
    'SUSPENDIDO' => 'Suspendido',
    _ => status,
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: appLime.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          color: appLime,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
