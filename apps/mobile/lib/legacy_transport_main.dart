import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repositories/admin_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/client_service_repository.dart';
import 'data/repositories/driver_presence_repository.dart';
import 'data/repositories/evidence_repository.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/service_event_repository.dart';
import 'data/repositories/service_repository.dart';
import 'data/repositories/tracking_repository.dart';
import 'data/services/api_client.dart';
import 'data/services/push_service.dart';
import 'data/services/background_tracking_service.dart';
import 'data/services/local_database.dart';
import 'data/services/location_service.dart';
import 'data/services/road_routing_service.dart';
import 'data/services/session_store.dart';
import 'data/services/sync_coordinator.dart';
import 'ui/core/app_scope.dart';
import 'ui/core/map_theme.dart';
import 'ui/core/push_navigation.dart';

Future<void> legacyTransportMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await mapThemeController.load();
    final sessionStore = await SessionStore.create();
    await sessionStore.expireIfNeeded();
    final localDatabase = await LocalDatabase.open();
    final apiClient = ApiClient(sessionStore: sessionStore);
    final locationService = LocationService();
    const roadRoutingService = RoadRoutingService();
    final trackingRepository = TrackingRepository(
      localDatabase: localDatabase,
      sessionStore: sessionStore,
    );
    final backgroundTrackingService = BackgroundTrackingService(
      locationService: locationService,
      trackingRepository: trackingRepository,
      sessionStore: sessionStore,
      localDatabase: localDatabase,
    );
    final syncCoordinator = SyncCoordinator(
      apiClient: apiClient,
      localDatabase: localDatabase,
      sessionStore: sessionStore,
      trackingRepository: trackingRepository,
    );
    backgroundTrackingService.onPositionPersisted = syncCoordinator.syncNow;
    syncCoordinator.onTrackingReady = backgroundTrackingService.start;
    syncCoordinator.onTrackingClosed = () =>
        backgroundTrackingService.stopCapture();

    final evidenceRepository = EvidenceRepository(
      localDatabase: localDatabase,
      sessionStore: sessionStore,
    );
    final serviceRepository = ServiceRepository(
      apiClient: apiClient,
      localDatabase: localDatabase,
      sessionStore: sessionStore,
    );
    final eventRepository = ServiceEventRepository(
      localDatabase: localDatabase,
      sessionStore: sessionStore,
      syncCoordinator: syncCoordinator,
      trackingRepository: trackingRepository,
      backgroundTrackingService: backgroundTrackingService,
    );
    final pushService = PushService(apiClient);
    // Tocar el aviso debe abrir el formulario de asignación, no sólo la app.
    pushService.onNotificationTap = handlePushTap;
    final authRepository = AuthRepository(
      apiClient: apiClient,
      sessionStore: sessionStore,
      localDatabase: localDatabase,
      pushService: pushService,
      locationService: locationService,
    );
    final adminRepository = AdminRepository(apiClient: apiClient);
    final clientServiceRepository = ClientServiceRepository(
      apiClient: apiClient,
    );
    final driverPresenceRepository = DriverPresenceRepository(
      apiClient: apiClient,
      locationService: locationService,
      backgroundTrackingService: backgroundTrackingService,
      sessionStore: sessionStore,
    );
    backgroundTrackingService.onTrackingStarting =
        driverPresenceRepository.pauseForRouteStart;
    final notificationRepository = NotificationRepository(
      apiClient: apiClient,
      pushService: pushService,
    );

    syncCoordinator.start();
    runApp(
      AppScope(
        authRepository: authRepository,
        adminRepository: adminRepository,
        clientServiceRepository: clientServiceRepository,
        driverPresenceRepository: driverPresenceRepository,
        notificationRepository: notificationRepository,
        serviceRepository: serviceRepository,
        eventRepository: eventRepository,
        evidenceRepository: evidenceRepository,
        locationService: locationService,
        roadRoutingService: roadRoutingService,
        sessionStore: sessionStore,
        trackingRepository: trackingRepository,
        backgroundTrackingService: backgroundTrackingService,
        syncCoordinator: syncCoordinator,
        child: const TransportControlApp(),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runBestEffort(
        backgroundTrackingService.recoverActiveSession(),
        'recuperación de tracking',
      );
      _runBestEffort(syncCoordinator.syncNow(), 'sincronización inicial');
      // El token de push se registraba SÓLO al iniciar sesión. Quien ya tenía
      // la sesión guardada abría la app y se quedaba sin token para siempre:
      // los avisos se creaban en el servidor pero no llegaban al teléfono.
      if (sessionStore.user != null) {
        _runBestEffort(
          pushService.registrarTrasIniciarSesion(),
          'registro de push',
        );
      }
    });
  } on Object catch (error) {
    runApp(_BootstrapFailureApp(message: error.toString()));
  }
}

void _runBestEffort(Future<void> future, String operation) {
  unawaited(
    future.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Falló $operation: $error\n$stackTrace');
    }),
  );
}

class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pudo iniciar Rutas Control',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
