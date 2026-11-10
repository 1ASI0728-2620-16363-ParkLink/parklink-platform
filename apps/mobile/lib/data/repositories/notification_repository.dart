import '../../domain/models/in_app_notification.dart';
import '../services/api_client.dart';
import '../services/push_service.dart';

class NotificationRepository {
  NotificationRepository({
    required ApiClient apiClient,
    PushService? pushService,
  }) : _apiClient = apiClient,
       _pushService = pushService;

  final ApiClient _apiClient;
  final PushService? _pushService;

  /// Avisos por los que ya se sonó, para no repetirlos en cada consulta.
  final Set<String> _yaAvisados = <String>{};
  bool _primeraCarga = true;

  Future<List<InAppNotification>> notifications() async {
    final response = await _apiClient.getJson('/notifications');
    final data = response['data'];
    final records =
        response['notifications'] ??
        (data is Map<String, dynamic> ? data['notifications'] : data);
    if (records is! List) return const [];
    final avisos =
        records
            .whereType<Map<String, dynamic>>()
            .map(InAppNotification.fromJson)
            .toList()
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
    await _sonarLosNuevos(avisos);
    return avisos;
  }

  /// Convierte en aviso del sistema todo lo que entra a la bandeja.
  ///
  /// La app consulta la bandeja cada pocos segundos; acá se detecta lo que no
  /// se había visto y se dibuja una notificación local. Así el aviso suena
  /// aunque el push no llegue nunca — el caso del iPhone sin la capacidad de
  /// push firmada, y el de Android con la app en primer plano.
  Future<void> _sonarLosNuevos(List<InAppNotification> avisos) async {
    final push = _pushService;
    if (push == null) return;

    // En la primera carga sólo se toma nota: si no, al abrir la app sonaría
    // de golpe todo el historial pendiente.
    if (_primeraCarga) {
      _primeraCarga = false;
      _yaAvisados.addAll(avisos.map((aviso) => aviso.id));
      return;
    }

    for (final aviso in avisos.reversed) {
      if (aviso.read || !_yaAvisados.add(aviso.id)) continue;
      try {
        await push.mostrarAvisoLocal(
          id: aviso.id.hashCode,
          titulo: aviso.title,
          cuerpo: aviso.message,
          payload: aviso.requestId,
        );
      } catch (_) {
        // Que no suene no puede romper la carga de la bandeja.
      }
    }
  }

  Future<void> markRead(String notificationId) async {
    await _apiClient.patchJson('/notifications/$notificationId/read', const {});
  }

  Future<void> sendEmergency({String? serviceId}) async {
    await _apiClient.postJson('/notifications/emergency', {
      'serviceId': ?serviceId,
    });
  }
}
