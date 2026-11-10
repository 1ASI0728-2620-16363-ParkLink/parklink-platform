import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

/// Canal propio para Android: sin él, con la app abierta el aviso no se muestra.
const AndroidNotificationChannel _canal = AndroidNotificationChannel(
  'centinela_avisos',
  'Avisos de Centinela',
  description: 'Solicitudes de servicio y asignaciones',
  importance: Importance.high,
);

/// Se ejecuta en un aislado aparte cuando llega un mensaje con la app cerrada.
/// Debe ser una función de nivel superior: Flutter la invoca sin contexto.
@pragma('vm:entry-point')
Future<void> manejarMensajeEnSegundoPlano(RemoteMessage mensaje) async {
  // El sistema ya dibuja la notificación; aquí sólo se registra para depurar.
  debugPrint('Push en segundo plano: ${mensaje.messageId}');
}

/// Notificaciones push nativas.
///
/// El token identifica a la instalación, no a la persona, así que se registra
/// después de iniciar sesión y se da de baja al cerrarla: si dos personas usan
/// el mismo teléfono, los avisos no se cruzan.
class PushService {
  PushService(this._apiClient);

  final ApiClient _apiClient;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  String? _tokenRegistrado;
  StreamSubscription<String>? _suscripcionRenovacion;
  bool _iniciado = false;

  /// Callback para que la app navegue al tocar un aviso.
  void Function(Map<String, dynamic> datos)? onNotificationTap;

  /// Arranca Firebase y los avisos locales. Es seguro llamarlo varias veces.
  Future<void> inicializar() async {
    if (_iniciado) return;
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // Sin ficheros de configuración de Firebase la app debe seguir siendo
      // usable: lo único que se pierde son los avisos push.
      debugPrint('Firebase no disponible, push desactivado: $error');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(manejarMensajeEnSegundoPlano);

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (respuesta) {
        final datos = respuesta.payload;
        if (datos != null) onNotificationTap?.call({'raw': datos});
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_canal);

    // Con la app en primer plano iOS no muestra nada por su cuenta.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    FirebaseMessaging.onMessage.listen(_mostrarEnPrimerPlano);
    FirebaseMessaging.onMessageOpenedApp.listen((mensaje) {
      onNotificationTap?.call(Map<String, dynamic>.from(mensaje.data));
    });

    // Si la app estaba cerrada, el aviso que la abrió no pasa por
    // onMessageOpenedApp: hay que pedirlo una vez, o el dato se pierde.
    final inicial = await FirebaseMessaging.instance.getInitialMessage();
    if (inicial != null) {
      onNotificationTap?.call(Map<String, dynamic>.from(inicial.data));
    }

    _iniciado = true;
  }

  /// Pide permiso y registra el token contra la API. Se llama tras iniciar sesión.
  Future<void> registrarTrasIniciarSesion() async {
    await inicializar();
    if (!_iniciado) return;

    final permiso = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permiso.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('El usuario rechazó los avisos push');
      return;
    }

    // En iOS el token de FCM no existe hasta que APNs entrega el suyo.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns == null) {
        debugPrint(
          'APNs todavía no entregó token; se reintentará al refrescarse',
        );
      }
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _enviarToken(token);

    // El token puede rotar en cualquier momento: hay que reenviarlo.
    await _suscripcionRenovacion?.cancel();
    _suscripcionRenovacion = FirebaseMessaging.instance.onTokenRefresh.listen(
      (nuevo) => _enviarToken(nuevo),
    );
  }

  Future<void> _enviarToken(String token) async {
    try {
      await _apiClient.postJson('/notifications/push-tokens', {
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      });
      _tokenRegistrado = token;
    } catch (error) {
      // Que falle el registro no debe impedir usar la app.
      debugPrint('No se pudo registrar el token de push: $error');
    }
  }

  /// Da de baja el aparato para que no siga recibiendo avisos ajenos.
  Future<void> darDeBajaAlCerrarSesion() async {
    await _suscripcionRenovacion?.cancel();
    _suscripcionRenovacion = null;
    final token = _tokenRegistrado;
    if (token == null) return;
    _tokenRegistrado = null;
    try {
      await _apiClient.delete('/notifications/push-tokens/$token');
    } catch (error) {
      debugPrint('No se pudo dar de baja el token de push: $error');
    }
  }

  Future<void> _mostrarEnPrimerPlano(RemoteMessage mensaje) async {
    final aviso = mensaje.notification;
    if (aviso == null) return;
    await _local.show(
      aviso.hashCode,
      aviso.title,
      aviso.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _canal.id,
          _canal.name,
          channelDescription: _canal.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: mensaje.data['serviceRequestId'] as String?,
    );
  }

  /// Muestra un aviso del sistema sin pasar por FCM.
  ///
  /// Las notificaciones locales las dibuja la app, así que NO necesitan token
  /// ni el permiso de push. Es la única vía que funciona en un iPhone cuyo
  /// perfil no incluye la capacidad de push, y también cubre el caso de
  /// Android con la app en primer plano, donde el sistema no muestra el push
  /// por su cuenta.
  ///
  /// Sólo llega si la app está viva: iOS suspende las apps en segundo plano,
  /// así que no reemplaza al push real cuando está cerrada.
  Future<void> mostrarAvisoLocal({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    await inicializar();
    if (!_iniciado) return;
    await _local.show(
      id,
      titulo,
      cuerpo,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _canal.id,
          _canal.name,
          channelDescription: _canal.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}
