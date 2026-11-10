import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Solicitud que quedó pendiente de abrir porque el usuario tocó un aviso push.
///
/// El backend manda en el push `action: OPEN_ASSIGNMENT_FORM` junto con el id
/// de la solicitud, para que al tocarlo se abra directamente el formulario de
/// asignación. Este notificador es el puente entre el servicio de push —que no
/// conoce la navegación— y la pantalla de administración, que sí sabe abrirlo.
///
/// Es global, igual que la preferencia de tema del mapa, porque el aviso puede
/// llegar antes de que exista la pantalla que debe atenderlo: al tocar un push
/// con la app cerrada, Flutter arranca de cero y el dato tiene que sobrevivir
/// hasta que el shell esté montado.
final pendingAssignmentRequestId = ValueNotifier<String?>(null);

/// Acción que el backend pide ejecutar al tocar el aviso.
const openAssignmentFormAction = 'OPEN_ASSIGNMENT_FORM';

/// Traduce los datos del push a una solicitud pendiente de abrir.
///
/// FCM sólo transporta cadenas en `data`, así que todo llega como texto.
void handlePushTap(Map<String, dynamic> datos) {
  final raw = datos['raw'];
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        handlePushTap(decoded);
        return;
      }
    } catch (_) {
      handlePushTap({
        'action': openAssignmentFormAction,
        'serviceRequestId': raw,
      });
      return;
    }
  }
  if (datos['action'] != openAssignmentFormAction) return;
  final id = datos['serviceRequestId'];
  if (id is! String || id.trim().isEmpty) return;
  pendingAssignmentRequestId.value = id.trim();
}
