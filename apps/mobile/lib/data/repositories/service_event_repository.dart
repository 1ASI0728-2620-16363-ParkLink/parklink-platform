import 'package:uuid/uuid.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/location_point.dart';
import '../../domain/models/transport_service.dart';
import '../services/background_tracking_service.dart';
import '../services/local_database.dart';
import '../services/session_store.dart';
import '../services/sync_coordinator.dart';
import 'tracking_repository.dart';

class ServiceEventRepository {
  ServiceEventRepository({
    required LocalDatabase localDatabase,
    required SessionStore sessionStore,
    required SyncCoordinator syncCoordinator,
    required TrackingRepository trackingRepository,
    required BackgroundTrackingService backgroundTrackingService,
  }) : _localDatabase = localDatabase,
       _sessionStore = sessionStore,
       _syncCoordinator = syncCoordinator,
       _trackingRepository = trackingRepository,
       _backgroundTrackingService = backgroundTrackingService;

  final LocalDatabase _localDatabase;
  final SessionStore _sessionStore;
  final SyncCoordinator _syncCoordinator;
  final TrackingRepository _trackingRepository;
  final BackgroundTrackingService _backgroundTrackingService;

  Future<bool> execute({
    required TransportService service,
    required ServiceAction action,
    LocationPoint? location,
    Map<String, dynamic> extra = const {},
    List<String> evidenceIds = const [],
  }) async {
    if (!service.allowedActions.contains(action)) {
      throw const AppFailure(
        'Esta acción ya no está permitida para el estado actual.',
        kind: AppFailureKind.conflict,
      );
    }
    if (action == ServiceAction.finish) {
      await _syncCoordinator.syncNow();
    }
    final owner = _owner;
    final deviceId = _sessionStore.serverDeviceId;
    if (deviceId == null) {
      throw const AppFailure(
        'El dispositivo no está autorizado. Inicia sesión nuevamente.',
        kind: AppFailureKind.authorization,
      );
    }
    final clientEventId = const Uuid().v4();
    final capturedAt = location?.capturedAt?.toUtc() ?? DateTime.now().toUtc();
    final activeSession = await _trackingRepository.activeSession();
    if (action == ServiceAction.start && activeSession != null) {
      throw const AppFailure(
        'Ya existe una sesión de seguimiento activa en este dispositivo.',
        kind: AppFailureKind.conflict,
      );
    }
    if (activeSession != null && activeSession.serviceId != service.id) {
      throw const AppFailure(
        'La sesión de seguimiento activa pertenece a otro servicio.',
        kind: AppFailureKind.conflict,
      );
    }
    if (_requiresTrackingSession(action) && activeSession == null) {
      throw const AppFailure(
        'Esta acción requiere una sesión de seguimiento activa.',
        kind: AppFailureKind.conflict,
      );
    }
    LocalTrackingSession? provisional;
    String? clientTrackingSessionId;
    if (action == ServiceAction.start) {
      clientTrackingSessionId = const Uuid().v4();
      provisional = await _trackingRepository.createProvisional(
        service,
        localId: clientTrackingSessionId,
      );
    }

    final payload = <String, dynamic>{
      'clientEventId': clientEventId,
      'capturedAt': capturedAt.toIso8601String(),
      'expectedVersion': service.statusVersion,
      'deviceId': deviceId,
      if (location != null) 'location': location.toCommandJson(),
      if (action == ServiceAction.start) 'locationPermissionGranted': true,
      if (activeSession != null && _usesTrackingSession(action))
        'trackingSessionId': activeSession.serverId ?? activeSession.localId,
      'clientTrackingSessionId': ?clientTrackingSessionId,
      ...extra,
    };
    final endpoint = _endpoint(service, action, extra);
    await _localDatabase.enqueueCommand(
      ownerUserId: owner,
      clientEventId: clientEventId,
      serviceId: service.id,
      kind: action.contractName,
      endpoint: endpoint,
      payload: payload,
      evidenceIds: evidenceIds,
    );
    final bool queued;
    try {
      // Finalizar espera a que el servidor acuse todas las posiciones, para no
      // cerrar el viaje con telemetría a medias. Pero si esa cola se traba, el
      // comando quedaba encolado para siempre y el servicio no salía nunca de
      // EN_DESTINO: se insiste vaciando posiciones antes de darse por vencido.
      var finishMustWait =
          action == ServiceAction.finish &&
          await _syncCoordinator.serviceHasUnacknowledgedPositions(
            owner,
            service.id,
          );
      for (var intento = 0; finishMustWait && intento < 3; intento++) {
        await _syncCoordinator.syncNow();
        finishMustWait = await _syncCoordinator
            .serviceHasUnacknowledgedPositions(owner, service.id);
      }
      queued = finishMustWait
          ? true
          : await _syncCoordinator.sendCommandNow(owner, clientEventId);
    } catch (_) {
      if (provisional != null) {
        await _localDatabase.closeTrackingSession(owner, provisional.localId);
      }
      rethrow;
    }

    if (queued && action == ServiceAction.start) {
      final permit = service.offlineStartPermit;
      if (permit == null || !permit.isValid) {
        await _localDatabase.deleteCommand(owner, clientEventId);
        if (provisional != null) {
          await _localDatabase.closeTrackingSession(owner, provisional.localId);
        }
        throw const AppFailure(
          'Para iniciar sin conexión necesitas un permiso offline vigente.',
          kind: AppFailureKind.authorization,
        );
      }
      await _backgroundTrackingService.start(provisional!);
    }
    return !queued;
  }

  bool _usesTrackingSession(ServiceAction action) => switch (action) {
    ServiceAction.stop ||
    ServiceAction.incident ||
    ServiceAction.finish ||
    ServiceAction.suspend => true,
    _ => false,
  };

  bool _requiresTrackingSession(ServiceAction action) => switch (action) {
    ServiceAction.stop || ServiceAction.finish => true,
    _ => false,
  };

  String _endpoint(
    TransportService service,
    ServiceAction action,
    Map<String, dynamic> extra,
  ) {
    final root = '/mobile/services/${service.id}';
    return switch (action) {
      ServiceAction.start => '$root/start',
      ServiceAction.stop => '$root/stops',
      ServiceAction.incident => '$root/incidents',
      ServiceAction.finish => '$root/finish',
      ServiceAction.suspend => '$root/suspend',
      ServiceAction.summary => throw ArgumentError(
        'SUMMARY se consulta con ServiceRepository.',
      ),
    };
  }

  Future<void> syncPending() => _syncCoordinator.syncNow();

  Future<int> pendingCount() async {
    final owner = _sessionStore.ownerUserId;
    if (owner == null) return 0;
    return (await _localDatabase.syncHealth(owner)).pendingCount;
  }

  Future<bool> hasPendingCommand(String serviceId) async {
    final owner = _sessionStore.ownerUserId;
    if (owner == null) return false;
    return _localDatabase.hasPendingCommandForService(owner, serviceId);
  }

  Future<bool> hasDeadLetter(String serviceId) async {
    final owner = _sessionStore.ownerUserId;
    if (owner == null) return false;
    return _localDatabase.hasDeadLetterForService(owner, serviceId);
  }

  String get _owner {
    final owner = _sessionStore.ownerUserId;
    if (owner == null) throw const SessionExpiredFailure();
    return owner;
  }
}
