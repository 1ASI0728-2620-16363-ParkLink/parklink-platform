import 'package:uuid/uuid.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/location_point.dart';
import '../../domain/models/tracking_position.dart';
import '../../domain/models/tracking_session.dart';
import '../../domain/models/transport_service.dart';
import '../services/local_database.dart';
import '../services/session_store.dart';

class TrackingRepository {
  TrackingRepository({
    required LocalDatabase localDatabase,
    required SessionStore sessionStore,
  }) : _localDatabase = localDatabase,
       _sessionStore = sessionStore;

  final LocalDatabase _localDatabase;
  final SessionStore _sessionStore;

  Future<LocalTrackingSession> createProvisional(
    TransportService service, {
    String? localId,
  }) async {
    final owner = _owner;
    final session = TrackingSession(
      localId: localId ?? const Uuid().v4(),
      id: null,
      serviceId: service.id,
      status: 'PROVISIONAL',
      policy: service.trackingSession?.policy ?? service.trackingPolicy,
    );
    await _localDatabase.saveTrackingSession(owner, session);
    return (await _localDatabase.trackingSession(owner, session.localId))!;
  }

  Future<LocalTrackingSession> materializeFromResponse({
    required String serviceId,
    required String localId,
    required Map<String, dynamic> response,
  }) async {
    final raw = response['trackingSession'] as Map<String, dynamic>?;
    if (raw == null) {
      throw const ApiFailure(
        'El inicio no devolvió una sesión de seguimiento.',
        kind: AppFailureKind.validation,
      );
    }
    final serverId = raw['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      throw const ApiFailure(
        'La sesión de seguimiento recibida está incompleta.',
        kind: AppFailureKind.validation,
      );
    }
    final provisional = await _localDatabase.trackingSession(_owner, localId);
    final session = TrackingSession(
      localId: localId,
      id: serverId,
      serviceId: serviceId,
      status: raw['status'] as String? ?? 'ACTIVE',
      policy: provisional?.policy ?? const TrackingPolicy(),
      lastSequence: (raw['lastSequence'] as num?)?.toInt() ?? 0,
    );
    await _localDatabase.saveTrackingSession(_owner, session);
    return (await _localDatabase.trackingSession(_owner, localId))!;
  }

  Future<TrackingPosition> persist(LocationPoint location) async {
    final session = await activeSession();
    if (session == null) {
      throw const StorageFailure('No hay una sesión de seguimiento activa.');
    }
    return _localDatabase.persistPosition(_owner, session, location);
  }

  Future<LocalTrackingSession?> activeSession() {
    return _localDatabase.activeTrackingSession(_owner);
  }

  Future<LocalTrackingSession?> restoreActiveSession(
    Iterable<TransportService> services,
  ) async {
    final existing = await activeSession();
    TrackingSession? serverSession;
    for (final service in services) {
      final session = service.trackingSession;
      if (session == null || !session.isActive || session.id == null) continue;
      serverSession = session;
      break;
    }

    if (existing != null && existing.serverId != serverSession?.id) {
      await _localDatabase.closeTrackingSession(_owner, existing.localId);
    }
    if (serverSession == null) return null;

    final restored = TrackingSession(
      localId: existing?.serverId == serverSession.id
          ? existing!.localId
          : serverSession.localId,
      id: serverSession.id,
      serviceId: serverSession.serviceId,
      status: serverSession.status,
      policy: serverSession.policy,
      lastSequence: serverSession.lastSequence,
    );
    await _localDatabase.saveTrackingSession(_owner, restored);
    return _localDatabase.trackingSession(_owner, restored.localId);
  }

  Future<void> closeActiveSession() async {
    final session = await activeSession();
    if (session == null) return;
    await _localDatabase.closeTrackingSession(_owner, session.localId);
  }

  Future<List<LocationPoint>> positionsForService(String serviceId) {
    return _localDatabase.positionsForService(_owner, serviceId);
  }

  String get _owner {
    final owner = _sessionStore.ownerUserId;
    if (owner == null) throw const SessionExpiredFailure();
    return owner;
  }
}
