import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/location_point.dart';
import '../../domain/models/tracking_position.dart';
import '../../domain/models/tracking_session.dart';
import '../../domain/models/transport_service.dart';

class LocalTrackingSession {
  const LocalTrackingSession({
    required this.ownerUserId,
    required this.localId,
    required this.serverId,
    required this.serviceId,
    required this.status,
    required this.policy,
  });

  final String ownerUserId;
  final String localId;
  final String? serverId;
  final String serviceId;
  final String status;
  final TrackingPolicy policy;
}

class PendingCommand {
  const PendingCommand({
    required this.ownerUserId,
    required this.clientEventId,
    required this.serviceId,
    required this.kind,
    required this.endpoint,
    required this.payload,
    required this.evidenceIds,
    required this.attempts,
  });

  final String ownerUserId;
  final String clientEventId;
  final String serviceId;
  final String kind;
  final String endpoint;
  final Map<String, dynamic> payload;
  final List<String> evidenceIds;
  final int attempts;
}

class PendingEvidence {
  const PendingEvidence({
    required this.ownerUserId,
    required this.clientEvidenceId,
    required this.serviceId,
    required this.filePath,
    required this.mimeType,
    required this.sha256,
    required this.capturedAt,
    required this.location,
    required this.serverId,
    this.attempts = 0,
  });

  final String ownerUserId;
  final String clientEvidenceId;
  final String serviceId;
  final String filePath;
  final String mimeType;
  final String sha256;
  final DateTime capturedAt;
  final LocationPoint location;
  final String? serverId;
  final int attempts;
}

class SyncHealth {
  const SyncHealth({
    required this.pendingCount,
    required this.deadLetterCount,
    required this.lastError,
  });

  final int pendingCount;
  final int deadLetterCount;
  final String? lastError;
}

class LocalDatabase {
  LocalDatabase._(this._database);

  static const _version = 7;
  static const _maxAttempts = 8;
  final Database _database;

  static Future<LocalDatabase> open({String? databasePath}) async {
    final path =
        databasePath ?? p.join(await getDatabasesPath(), 'mobile_driver.db');
    final database = await openDatabase(
      path,
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 4) {
          // Legacy rows had no owner and cannot be attributed safely. They are
          // removed instead of risking a cross-user disclosure or sync.
          for (final table in const [
            'cached_services',
            'pending_events',
            'pending_evidences',
            'service_snapshots',
            'tracking_sessions',
            'position_outbox',
            'command_outbox',
            'evidence_outbox',
            'sync_checkpoints',
          ]) {
            await db.execute('drop table if exists $table');
          }
          await _createSchema(db);
          return;
        }
        if (oldVersion < 5) {
          await _migrateToV5(db);
        }
        if (oldVersion < 6) {
          await _migrateToV6(db);
        }
        if (oldVersion < 7) {
          await _migrateToV7(db);
        }
      },
    );
    return LocalDatabase._(database);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      create table service_snapshots (
        owner_user_id text not null,
        service_id text not null,
        json text not null,
        synced_at text not null,
        primary key (owner_user_id, service_id)
      )
    ''');
    await db.execute('''
      create table tracking_sessions (
        owner_user_id text not null,
        local_id text not null,
        server_id text,
        service_id text not null,
        status text not null,
        policy_json text not null,
        next_sequence integer not null default 1,
        updated_at text not null,
        primary key (owner_user_id, local_id)
      )
    ''');
    await db.execute('''
      create unique index tracking_sessions_server_idx
      on tracking_sessions(owner_user_id, server_id)
      where server_id is not null
    ''');
    await db.execute('''
      create table position_outbox (
        owner_user_id text not null,
        client_position_id text not null,
        session_local_id text not null,
        service_id text not null,
        sequence_number integer not null,
        payload_json text not null,
        attempts integer not null default 0,
        next_attempt_at text not null,
        last_error text,
        dead_letter integer not null default 0,
        created_at text not null,
        acked_at text,
        primary key (owner_user_id, client_position_id),
        unique (owner_user_id, session_local_id, sequence_number)
      )
    ''');
    await db.execute('''
      create index position_outbox_due_idx
      on position_outbox(owner_user_id, dead_letter, acked_at, next_attempt_at)
    ''');
    await db.execute('''
      create table command_outbox (
        owner_user_id text not null,
        client_event_id text not null,
        service_id text not null,
        kind text not null,
        endpoint text not null,
        payload_json text not null,
        evidence_ids_json text not null default '[]',
        attempts integer not null default 0,
        next_attempt_at text not null,
        last_error text,
        dead_letter integer not null default 0,
        created_at text not null,
        acked_at text,
        primary key (owner_user_id, client_event_id)
      )
    ''');
    await db.execute('''
      create index command_outbox_due_idx
      on command_outbox(owner_user_id, dead_letter, acked_at, next_attempt_at, created_at)
    ''');
    await db.execute('''
      create table evidence_outbox (
        owner_user_id text not null,
        client_evidence_id text not null,
        service_id text not null,
        file_path text not null,
        mime_type text not null,
        sha256 text not null,
        captured_at text not null,
        location_json text not null,
        server_id text,
        attempts integer not null default 0,
        next_attempt_at text not null,
        last_error text,
        dead_letter integer not null default 0,
        created_at text not null,
        uploaded_at text,
        primary key (owner_user_id, client_evidence_id)
      )
    ''');
  }

  static Future<void> _migrateToV5(DatabaseExecutor db) async {
    await db.execute('''
      create table service_snapshots_v5 (
        owner_user_id text not null,
        service_id text not null,
        json text not null,
        synced_at text not null,
        primary key (owner_user_id, service_id)
      )
    ''');
    await db.execute('''
      insert into service_snapshots_v5 (
        owner_user_id, service_id, json, synced_at
      )
      select owner_user_id, service_id, json, synced_at
      from service_snapshots
    ''');
    await db.execute('drop table service_snapshots');
    await db.execute(
      'alter table service_snapshots_v5 rename to service_snapshots',
    );

    await db.execute('''
      create table tracking_sessions_v5 (
        owner_user_id text not null,
        local_id text not null,
        server_id text,
        service_id text not null,
        status text not null,
        policy_json text not null,
        next_sequence integer not null default 1,
        updated_at text not null,
        primary key (owner_user_id, local_id)
      )
    ''');
    await db.execute('''
      insert into tracking_sessions_v5 (
        owner_user_id, local_id, server_id, service_id, status, policy_json,
        next_sequence, updated_at
      )
      select owner_user_id, local_id, server_id, service_id, status, policy_json,
        next_sequence, updated_at
      from tracking_sessions
    ''');
    await db.execute('drop table tracking_sessions');
    await db.execute(
      'alter table tracking_sessions_v5 rename to tracking_sessions',
    );
    await db.execute('''
      create unique index tracking_sessions_server_idx
      on tracking_sessions(owner_user_id, server_id)
      where server_id is not null
    ''');

    await db.execute('''
      create table position_outbox_v5 (
        owner_user_id text not null,
        client_position_id text not null,
        session_local_id text not null,
        service_id text not null,
        sequence_number integer not null,
        payload_json text not null,
        attempts integer not null default 0,
        next_attempt_at text not null,
        last_error text,
        dead_letter integer not null default 0,
        created_at text not null,
        acked_at text,
        primary key (owner_user_id, client_position_id),
        unique (owner_user_id, session_local_id, sequence_number)
      )
    ''');
    await db.execute('''
      insert into position_outbox_v5 (
        owner_user_id, client_position_id, session_local_id, service_id,
        sequence_number, payload_json, attempts, next_attempt_at, last_error,
        dead_letter, created_at, acked_at
      )
      select owner_user_id, client_position_id, session_local_id, service_id,
        sequence_number, payload_json, attempts, next_attempt_at, last_error,
        dead_letter, created_at, acked_at
      from position_outbox
    ''');
    await db.execute('drop table position_outbox');
    await db.execute(
      'alter table position_outbox_v5 rename to position_outbox',
    );
    await db.execute('''
      create index position_outbox_due_idx
      on position_outbox(owner_user_id, dead_letter, acked_at, next_attempt_at)
    ''');

    await db.execute('''
      create table command_outbox_v5 (
        owner_user_id text not null,
        client_event_id text not null,
        service_id text not null,
        kind text not null,
        endpoint text not null,
        payload_json text not null,
        evidence_ids_json text not null default '[]',
        attempts integer not null default 0,
        next_attempt_at text not null,
        last_error text,
        dead_letter integer not null default 0,
        created_at text not null,
        acked_at text,
        primary key (owner_user_id, client_event_id)
      )
    ''');
    await db.execute('''
      insert into command_outbox_v5 (
        owner_user_id, client_event_id, service_id, kind, endpoint,
        payload_json, evidence_ids_json, attempts, next_attempt_at, last_error,
        dead_letter, created_at, acked_at
      )
      select owner_user_id, client_event_id, service_id, kind, endpoint,
        payload_json, evidence_ids_json, attempts, next_attempt_at, last_error,
        dead_letter, created_at, acked_at
      from command_outbox
    ''');
    await db.execute('drop table command_outbox');
    await db.execute('alter table command_outbox_v5 rename to command_outbox');
    await db.execute('''
      create index command_outbox_due_idx
      on command_outbox(owner_user_id, dead_letter, acked_at, next_attempt_at, created_at)
    ''');

    await db.execute('''
      create table evidence_outbox_v5 (
        owner_user_id text not null,
        client_evidence_id text not null,
        service_id text not null,
        file_path text not null,
        mime_type text not null,
        sha256 text not null,
        captured_at text not null,
        location_json text not null,
        server_id text,
        attempts integer not null default 0,
        next_attempt_at text not null,
        last_error text,
        dead_letter integer not null default 0,
        created_at text not null,
        uploaded_at text,
        primary key (owner_user_id, client_evidence_id)
      )
    ''');
    await db.execute('''
      insert into evidence_outbox_v5 (
        owner_user_id, client_evidence_id, service_id, file_path, mime_type,
        sha256, captured_at, location_json, server_id, attempts,
        next_attempt_at, last_error, dead_letter, created_at, uploaded_at
      )
      select owner_user_id, client_evidence_id, service_id, file_path, mime_type,
        sha256, captured_at, location_json, server_id, attempts,
        next_attempt_at, last_error, dead_letter, created_at, uploaded_at
      from evidence_outbox
    ''');
    await db.execute('drop table evidence_outbox');
    await db.execute(
      'alter table evidence_outbox_v5 rename to evidence_outbox',
    );
    await db.execute('drop table if exists sync_checkpoints');

    final batch = db.batch();
    for (final row in await db.query('service_snapshots')) {
      final snapshot =
          jsonDecode(row['json']! as String) as Map<String, dynamic>;
      batch.update(
        'service_snapshots',
        {'json': jsonEncode(_canonicalServiceSnapshot(snapshot))},
        where: 'owner_user_id = ? and service_id = ?',
        whereArgs: [row['owner_user_id'], row['service_id']],
      );
    }
    for (final row in await db.query('tracking_sessions')) {
      final policy =
          jsonDecode(row['policy_json']! as String) as Map<String, dynamic>;
      batch.update(
        'tracking_sessions',
        {'policy_json': jsonEncode(_canonicalTrackingPolicy(policy))},
        where: 'owner_user_id = ? and local_id = ?',
        whereArgs: [row['owner_user_id'], row['local_id']],
      );
    }
    for (final row in await db.query('command_outbox')) {
      final kind = row['kind']! as String;
      batch.update(
        'command_outbox',
        {'kind': _canonicalAction(kind)},
        where: 'owner_user_id = ? and client_event_id = ?',
        whereArgs: [row['owner_user_id'], row['client_event_id']],
      );
    }
    for (final row in await db.query('position_outbox')) {
      final payload =
          jsonDecode(row['payload_json']! as String) as Map<String, dynamic>;
      batch.update(
        'position_outbox',
        {'payload_json': jsonEncode(_canonicalLocation(payload))},
        where: 'owner_user_id = ? and client_position_id = ?',
        whereArgs: [row['owner_user_id'], row['client_position_id']],
      );
    }
    for (final row in await db.query('evidence_outbox')) {
      final location =
          jsonDecode(row['location_json']! as String) as Map<String, dynamic>;
      batch.update(
        'evidence_outbox',
        {'location_json': jsonEncode(_canonicalLocation(location))},
        where: 'owner_user_id = ? and client_evidence_id = ?',
        whereArgs: [row['owner_user_id'], row['client_evidence_id']],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _migrateToV6(DatabaseExecutor db) async {
    await db.update(
      'position_outbox',
      {
        'attempts': 0,
        'next_attempt_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
        'dead_letter': 0,
      },
      where:
          "acked_at is null and lower(last_error) like '%request body is invalid%'",
    );
  }

  static Future<void> _migrateToV7(DatabaseExecutor db) async {
    await db.delete(
      'position_outbox',
      where:
          "dead_letter = 1 and lower(last_error) like '%sequence belongs to another position%'",
    );
  }

  Future<void> replaceServiceSnapshots(
    String ownerUserId,
    List<TransportService> services,
  ) async {
    await _database.transaction((transaction) async {
      await transaction.delete(
        'service_snapshots',
        where: 'owner_user_id = ?',
        whereArgs: [ownerUserId],
      );
      for (final service in services) {
        await _upsertSnapshot(transaction, ownerUserId, service);
      }
    });
  }

  Future<void> upsertServiceSnapshot(
    String ownerUserId,
    TransportService service,
  ) {
    return _upsertSnapshot(_database, ownerUserId, service);
  }

  Future<void> _upsertSnapshot(
    DatabaseExecutor db,
    String ownerUserId,
    TransportService service,
  ) async {
    final snapshotJson = service.toJson()..remove('offlineStartPermit');
    await db.insert('service_snapshots', {
      'owner_user_id': ownerUserId,
      'service_id': service.id,
      'json': jsonEncode(snapshotJson),
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TransportService>> serviceSnapshots(String ownerUserId) async {
    final rows = await _database.query(
      'service_snapshots',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'synced_at desc',
    );
    return rows.map(_serviceFromRow).toList();
  }

  Future<TransportService?> serviceSnapshot(
    String ownerUserId,
    String serviceId,
  ) async {
    final rows = await _database.query(
      'service_snapshots',
      where: 'owner_user_id = ? and service_id = ?',
      whereArgs: [ownerUserId, serviceId],
      limit: 1,
    );
    return rows.isEmpty ? null : _serviceFromRow(rows.first);
  }

  TransportService _serviceFromRow(Map<String, Object?> row) =>
      TransportService.fromJson(
        jsonDecode(row['json']! as String) as Map<String, dynamic>,
      );

  Future<void> enqueueCommand({
    required String ownerUserId,
    required String clientEventId,
    required String serviceId,
    required String kind,
    required String endpoint,
    required Map<String, dynamic> payload,
    List<String> evidenceIds = const [],
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.insert('command_outbox', {
      'owner_user_id': ownerUserId,
      'client_event_id': clientEventId,
      'service_id': serviceId,
      'kind': kind,
      'endpoint': endpoint,
      'payload_json': jsonEncode(payload),
      'evidence_ids_json': jsonEncode(evidenceIds),
      'next_attempt_at': now,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<PendingCommand?> command(
    String ownerUserId,
    String clientEventId,
  ) async {
    final rows = await _database.query(
      'command_outbox',
      where: 'owner_user_id = ? and client_event_id = ? and acked_at is null',
      whereArgs: [ownerUserId, clientEventId],
      limit: 1,
    );
    return rows.isEmpty ? null : _commandFromRow(rows.first);
  }

  Future<String?> commandDeadLetterError(
    String ownerUserId,
    String clientEventId,
  ) async {
    final rows = await _database.query(
      'command_outbox',
      columns: ['last_error'],
      where: 'owner_user_id = ? and client_event_id = ? and dead_letter = 1',
      whereArgs: [ownerUserId, clientEventId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['last_error'] as String?;
  }

  Future<List<PendingCommand>> pendingCommands(String ownerUserId) async {
    final rows = await _database.rawQuery(
      '''
      select c.* from command_outbox c
      where c.owner_user_id = ?
        and c.acked_at is null
        and c.dead_letter = 0
        and c.next_attempt_at <= ?
        and not exists (
          select 1 from command_outbox predecessor
          where predecessor.owner_user_id = c.owner_user_id
            and predecessor.service_id = c.service_id
            and predecessor.dead_letter = 1
            and predecessor.created_at < c.created_at
        )
      order by c.created_at asc
    ''',
      [ownerUserId, DateTime.now().toUtc().toIso8601String()],
    );
    return rows.map(_commandFromRow).toList();
  }

  PendingCommand _commandFromRow(Map<String, Object?> row) => PendingCommand(
    ownerUserId: row['owner_user_id']! as String,
    clientEventId: row['client_event_id']! as String,
    serviceId: row['service_id']! as String,
    kind: row['kind']! as String,
    endpoint: row['endpoint']! as String,
    payload: jsonDecode(row['payload_json']! as String) as Map<String, dynamic>,
    evidenceIds: (jsonDecode(row['evidence_ids_json']! as String) as List)
        .cast<String>(),
    attempts: row['attempts']! as int,
  );

  Future<void> markCommandAcknowledged(
    String ownerUserId,
    String clientEventId,
  ) async {
    await _database.update(
      'command_outbox',
      {
        'acked_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
      },
      where: 'owner_user_id = ? and client_event_id = ?',
      whereArgs: [ownerUserId, clientEventId],
    );
  }

  Future<void> deleteCommand(String ownerUserId, String clientEventId) {
    return _database.delete(
      'command_outbox',
      where: 'owner_user_id = ? and client_event_id = ?',
      whereArgs: [ownerUserId, clientEventId],
    );
  }

  Future<void> failCommand(
    PendingCommand command,
    String error, {
    required bool retryable,
  }) {
    return _failOutboxRow(
      table: 'command_outbox',
      ownerUserId: command.ownerUserId,
      idColumn: 'client_event_id',
      id: command.clientEventId,
      attempts: command.attempts,
      error: error,
      retryable: retryable,
    );
  }

  Future<bool> hasPendingCommandForService(
    String ownerUserId,
    String serviceId,
  ) async {
    final result = Sqflite.firstIntValue(
      await _database.rawQuery(
        '''select count(*) from command_outbox
           where owner_user_id = ? and service_id = ?
             and acked_at is null and dead_letter = 0''',
        [ownerUserId, serviceId],
      ),
    );
    return (result ?? 0) > 0;
  }

  Future<bool> hasDeadLetterForService(
    String ownerUserId,
    String serviceId,
  ) async {
    final count = Sqflite.firstIntValue(
      await _database.rawQuery(
        '''select count(*) from command_outbox
           where owner_user_id = ? and service_id = ? and dead_letter = 1''',
        [ownerUserId, serviceId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> saveTrackingSession(
    String ownerUserId,
    TrackingSession session,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await _database.query(
      'tracking_sessions',
      columns: ['next_sequence'],
      where: 'owner_user_id = ? and local_id = ?',
      whereArgs: [ownerUserId, session.localId],
      limit: 1,
    );
    final localNextSequence = existing.isEmpty
        ? 1
        : existing.first['next_sequence']! as int;
    final serverNextSequence = session.lastSequence + 1;
    await _database.insert('tracking_sessions', {
      'owner_user_id': ownerUserId,
      'local_id': session.localId,
      'server_id': session.id,
      'service_id': session.serviceId,
      'status': session.status,
      'policy_json': jsonEncode(session.policy.toJson()),
      'next_sequence': localNextSequence > serverNextSequence
          ? localNextSequence
          : serverNextSequence,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<LocalTrackingSession?> activeTrackingSession(
    String ownerUserId,
  ) async {
    final rows = await _database.query(
      'tracking_sessions',
      where: "owner_user_id = ? and status in ('ACTIVE', 'PROVISIONAL')",
      whereArgs: [ownerUserId],
      orderBy: 'updated_at desc',
      limit: 1,
    );
    return rows.isEmpty ? null : _trackingSessionFromRow(rows.first);
  }

  Future<LocalTrackingSession?> trackingSession(
    String ownerUserId,
    String localId,
  ) async {
    final rows = await _database.query(
      'tracking_sessions',
      where: 'owner_user_id = ? and local_id = ?',
      whereArgs: [ownerUserId, localId],
      limit: 1,
    );
    return rows.isEmpty ? null : _trackingSessionFromRow(rows.first);
  }

  Future<List<LocalTrackingSession>> trackingSessionsWithPendingPositions(
    String ownerUserId,
  ) async {
    final rows = await _database.rawQuery(
      '''
      select distinct s.*
      from tracking_sessions s
      join position_outbox p
        on p.owner_user_id = s.owner_user_id
       and p.session_local_id = s.local_id
      where s.owner_user_id = ?
        and s.server_id is not null
        and p.acked_at is null
        and p.dead_letter = 0
      order by s.updated_at asc
    ''',
      [ownerUserId],
    );
    return rows.map(_trackingSessionFromRow).toList();
  }

  LocalTrackingSession _trackingSessionFromRow(Map<String, Object?> row) =>
      LocalTrackingSession(
        ownerUserId: row['owner_user_id']! as String,
        localId: row['local_id']! as String,
        serverId: row['server_id'] as String?,
        serviceId: row['service_id']! as String,
        status: row['status']! as String,
        policy: TrackingPolicy.fromJson(
          jsonDecode(row['policy_json']! as String) as Map<String, dynamic>,
        ),
      );

  Future<void> closeTrackingSession(String ownerUserId, String localId) async {
    await _database.update(
      'tracking_sessions',
      {
        'status': 'CLOSED',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'owner_user_id = ? and local_id = ?',
      whereArgs: [ownerUserId, localId],
    );
  }

  Future<void> closeAllActiveTrackingSessions(String ownerUserId) async {
    await _database.update(
      'tracking_sessions',
      {
        'status': 'CLOSED',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: "owner_user_id = ? and status in ('ACTIVE', 'PROVISIONAL')",
      whereArgs: [ownerUserId],
    );
  }

  Future<TrackingPosition> persistPosition(
    String ownerUserId,
    LocalTrackingSession session,
    LocationPoint location,
  ) async {
    return _database.transaction((transaction) async {
      final rows = await transaction.query(
        'tracking_sessions',
        columns: ['next_sequence'],
        where: 'owner_user_id = ? and local_id = ?',
        whereArgs: [ownerUserId, session.localId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const StorageFailure(
          'No existe una sesión local para guardar la posición.',
        );
      }
      final sequence = rows.first['next_sequence']! as int;
      await transaction.update(
        'tracking_sessions',
        {
          'next_sequence': sequence + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'owner_user_id = ? and local_id = ?',
        whereArgs: [ownerUserId, session.localId],
      );
      final position = TrackingPosition(
        clientPositionId: const Uuid().v4(),
        sequence: sequence,
        location: location,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await transaction.insert('position_outbox', {
        'owner_user_id': ownerUserId,
        'client_position_id': position.clientPositionId,
        'session_local_id': session.localId,
        'service_id': session.serviceId,
        'sequence_number': sequence,
        'payload_json': jsonEncode(position.toJson()),
        'next_attempt_at': now,
        'created_at': now,
      });
      return position;
    });
  }

  Future<List<TrackingPosition>> pendingPositions(
    String ownerUserId,
    LocalTrackingSession session, {
    required int limit,
  }) async {
    if (session.serverId == null) return const [];
    final rows = await _database.query(
      'position_outbox',
      where:
          'owner_user_id = ? and session_local_id = ? and acked_at is null and dead_letter = 0 and next_attempt_at <= ?',
      whereArgs: [
        ownerUserId,
        session.localId,
        DateTime.now().toUtc().toIso8601String(),
      ],
      orderBy: 'sequence_number asc',
      limit: limit,
    );
    return rows.map((row) {
      final json =
          jsonDecode(row['payload_json']! as String) as Map<String, dynamic>;
      final point = LocationPoint.fromJson(json);
      final sequence = row['sequence_number']! as int;
      final clientId = row['client_position_id']! as String;
      return TrackingPosition(
        clientPositionId: clientId,
        sequence: sequence,
        location: point,
      );
    }).toList();
  }

  Future<List<LocationPoint>> positionsForService(
    String ownerUserId,
    String serviceId, {
    int limit = 2000,
  }) async {
    final rows = await _database.query(
      'position_outbox',
      columns: ['payload_json'],
      where: 'owner_user_id = ? and service_id = ?',
      whereArgs: [ownerUserId, serviceId],
      orderBy: 'sequence_number desc',
      limit: limit,
    );
    return rows.reversed
        .map(
          (row) => LocationPoint.fromJson(
            jsonDecode(row['payload_json']! as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> acknowledgePositions(
    String ownerUserId,
    Set<String> clientIds,
  ) async {
    if (clientIds.isEmpty) return;
    final marks = List.filled(clientIds.length, '?').join(',');
    await _database.rawUpdate(
      '''update position_outbox set acked_at = ?, last_error = null
         where owner_user_id = ? and client_position_id in ($marks)''',
      [DateTime.now().toUtc().toIso8601String(), ownerUserId, ...clientIds],
    );
  }

  Future<void> failPositions(
    String ownerUserId,
    List<TrackingPosition> positions,
    String error, {
    required bool retryable,
  }) async {
    for (final position in positions) {
      final rows = await _database.query(
        'position_outbox',
        columns: ['attempts'],
        where: 'owner_user_id = ? and client_position_id = ?',
        whereArgs: [ownerUserId, position.clientPositionId],
        limit: 1,
      );
      await _failOutboxRow(
        table: 'position_outbox',
        ownerUserId: ownerUserId,
        idColumn: 'client_position_id',
        id: position.clientPositionId,
        attempts: rows.isEmpty ? 0 : rows.first['attempts']! as int,
        error: error,
        retryable: retryable,
      );
    }
  }

  Future<bool> hasUnacknowledgedPositionsForService(
    String ownerUserId,
    String serviceId,
  ) async {
    final count = Sqflite.firstIntValue(
      await _database.rawQuery(
        '''select count(*) from position_outbox
           where owner_user_id = ? and service_id = ?
             and acked_at is null and dead_letter = 0''',
        [ownerUserId, serviceId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> enqueueEvidence(PendingEvidence evidence) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.insert('evidence_outbox', {
      'owner_user_id': evidence.ownerUserId,
      'client_evidence_id': evidence.clientEvidenceId,
      'service_id': evidence.serviceId,
      'file_path': evidence.filePath,
      'mime_type': evidence.mimeType,
      'sha256': evidence.sha256,
      'captured_at': evidence.capturedAt.toIso8601String(),
      'location_json': jsonEncode(evidence.location.toJson()),
      'next_attempt_at': now,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<PendingEvidence>> evidencesByIds(
    String ownerUserId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await _database.rawQuery(
      '''select * from evidence_outbox
         where owner_user_id = ? and client_evidence_id in ($marks)''',
      [ownerUserId, ...ids],
    );
    return rows.map(_evidenceFromRow).toList();
  }

  PendingEvidence _evidenceFromRow(Map<String, Object?> row) => PendingEvidence(
    ownerUserId: row['owner_user_id']! as String,
    clientEvidenceId: row['client_evidence_id']! as String,
    serviceId: row['service_id']! as String,
    filePath: row['file_path']! as String,
    mimeType: row['mime_type']! as String,
    sha256: row['sha256']! as String,
    capturedAt: DateTime.parse(row['captured_at']! as String).toUtc(),
    location: LocationPoint.fromJson(
      jsonDecode(row['location_json']! as String) as Map<String, dynamic>,
    ),
    serverId: row['server_id'] as String?,
    attempts: row['attempts']! as int,
  );

  Future<void> failEvidences(
    List<PendingEvidence> evidences,
    String error, {
    required bool retryable,
  }) async {
    for (final evidence in evidences) {
      await _failOutboxRow(
        table: 'evidence_outbox',
        ownerUserId: evidence.ownerUserId,
        idColumn: 'client_evidence_id',
        id: evidence.clientEvidenceId,
        attempts: evidence.attempts,
        error: error,
        retryable: retryable,
      );
    }
  }

  Future<void> markEvidenceUploaded(
    String ownerUserId,
    String clientEvidenceId, {
    String? serverId,
  }) async {
    await _database.update(
      'evidence_outbox',
      {
        'server_id': serverId,
        'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
      },
      where: 'owner_user_id = ? and client_evidence_id = ?',
      whereArgs: [ownerUserId, clientEvidenceId],
    );
  }

  Future<void> _failOutboxRow({
    required String table,
    required String ownerUserId,
    required String idColumn,
    required String id,
    required int attempts,
    required String error,
    required bool retryable,
  }) async {
    final nextAttempts = attempts + 1;
    final dead = !retryable || nextAttempts >= _maxAttempts;
    await _database.update(
      table,
      {
        'attempts': nextAttempts,
        'dead_letter': dead ? 1 : 0,
        'last_error': error,
        'next_attempt_at': DateTime.now()
            .toUtc()
            .add(_backoff(nextAttempts))
            .toIso8601String(),
      },
      where: 'owner_user_id = ? and $idColumn = ?',
      whereArgs: [ownerUserId, id],
    );
  }

  Duration _backoff(int attempts) {
    const seconds = [5, 15, 60, 300, 900, 1800, 3600, 7200];
    final index = (attempts - 1).clamp(0, seconds.length - 1).toInt();
    final base = seconds[index];
    final jitter = DateTime.now().millisecondsSinceEpoch % 3000;
    return Duration(seconds: base, milliseconds: jitter);
  }

  Future<SyncHealth> syncHealth(String ownerUserId) async {
    final counts = await _database.rawQuery('''
      select
        (select count(*) from command_outbox where owner_user_id = ? and acked_at is null and dead_letter = 0) +
        (select count(*) from position_outbox where owner_user_id = ? and acked_at is null and dead_letter = 0) +
        (select count(*) from evidence_outbox where owner_user_id = ? and uploaded_at is null and dead_letter = 0) as pending_count,
        (select count(*) from command_outbox where owner_user_id = ? and dead_letter = 1) +
        (select count(*) from position_outbox where owner_user_id = ? and dead_letter = 1) +
        (select count(*) from evidence_outbox where owner_user_id = ? and dead_letter = 1) as dead_count
    ''', List.filled(6, ownerUserId));
    final errors = await _database.rawQuery(
      '''
      select last_error from (
        select last_error, created_at from command_outbox where owner_user_id = ? and last_error is not null
        union all
        select last_error, created_at from position_outbox where owner_user_id = ? and last_error is not null
        union all
        select last_error, created_at from evidence_outbox where owner_user_id = ? and last_error is not null
      ) order by created_at desc limit 1
    ''',
      [ownerUserId, ownerUserId, ownerUserId],
    );
    return SyncHealth(
      pendingCount: counts.first['pending_count'] as int? ?? 0,
      deadLetterCount: counts.first['dead_count'] as int? ?? 0,
      lastError: errors.isEmpty ? null : errors.first['last_error'] as String?,
    );
  }

  Future<void> applyRetention(String ownerUserId) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 72))
        .toIso8601String();
    await _database.transaction((transaction) async {
      await transaction.delete(
        'position_outbox',
        where: 'owner_user_id = ? and acked_at is not null and acked_at < ?',
        whereArgs: [ownerUserId, cutoff],
      );
      await transaction.delete(
        'command_outbox',
        where: 'owner_user_id = ? and acked_at is not null and acked_at < ?',
        whereArgs: [ownerUserId, cutoff],
      );
    });
  }

  Future<List<String>> evidenceFilesEligibleForRetention(
    String ownerUserId,
  ) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    final rows = await _database.query(
      'evidence_outbox',
      columns: ['file_path'],
      where:
          'owner_user_id = ? and uploaded_at is not null and uploaded_at < ?',
      whereArgs: [ownerUserId, cutoff],
    );
    return rows.map((row) => row['file_path']! as String).toList();
  }

  Future<void> deleteRetainedEvidenceRow(String ownerUserId, String filePath) {
    return _database.delete(
      'evidence_outbox',
      where: 'owner_user_id = ? and file_path = ? and uploaded_at is not null',
      whereArgs: [ownerUserId, filePath],
    );
  }
}

Map<String, dynamic> _canonicalServiceSnapshot(Map<String, dynamic> source) {
  final json = Map<String, dynamic>.from(source);
  final geofences = <String, dynamic>{};
  final existingGeofences = json['geofences'];
  if (existingGeofences is Map<String, dynamic>) {
    geofences.addAll(existingGeofences);
  }
  final origin = json.remove('originGeofence');
  final destination = json.remove('destinationGeofence');
  if (origin is Map<String, dynamic>) geofences['origin'] = origin;
  if (destination is Map<String, dynamic>) {
    geofences['destination'] = destination;
  }
  for (final key in const ['origin', 'destination']) {
    final geofence = geofences[key];
    if (geofence is! Map<String, dynamic>) continue;
    final canonical = Map<String, dynamic>.from(geofence);
    canonical['radiusM'] ??= canonical.remove('radiusMeters');
    geofences[key] = canonical;
  }
  json['geofences'] = geofences;
  json['currentStatus'] = _canonicalStatus(json['currentStatus'] as String?);
  final actions = json['allowedActions'];
  if (actions is List) {
    json['allowedActions'] = actions
        .whereType<String>()
        .map(_canonicalAction)
        .toList();
  }

  final policy = json['trackingPolicy'];
  if (policy is Map<String, dynamic>) {
    json['trackingPolicy'] = _canonicalTrackingPolicy(policy);
  }
  final tracking = json['trackingSession'];
  if (tracking is Map<String, dynamic>) {
    final canonical = Map<String, dynamic>.from(tracking);
    canonical['clientSessionId'] ??= canonical.remove(
      'clientTrackingSessionId',
    );
    json['trackingSession'] = canonical;
  }
  json.remove('plannedRoute');
  final route = json['actualRoute'];
  if (route is List) {
    json['actualRoute'] = route
        .whereType<Map<String, dynamic>>()
        .map(_canonicalLocation)
        .toList();
  }
  final openStop = json['openStop'];
  if (openStop is Map<String, dynamic>) {
    json['openStop'] = _canonicalStop(openStop);
  }
  json.remove('stops');
  return json;
}

Map<String, dynamic> _canonicalTrackingPolicy(Map<String, dynamic> source) {
  final json = Map<String, dynamic>.from(source);
  json['activeIntervalSeconds'] ??= json.remove('intervalSeconds');
  json.remove('syncIntervalSeconds');
  json.remove('maximumAccuracyMeters');
  return json;
}

Map<String, dynamic> _canonicalLocation(Map<String, dynamic> source) {
  final json = Map<String, dynamic>.from(source);
  json['accuracyM'] ??= json.remove('accuracy');
  json['speedMps'] ??= json.remove('speed');
  json['headingDeg'] ??= json.remove('heading');
  json['altitudeM'] ??= json.remove('altitude');
  return json;
}

Map<String, dynamic> _canonicalStop(Map<String, dynamic> source) {
  final json = Map<String, dynamic>.from(source);
  final latitude = json.remove('latitude');
  final longitude = json.remove('longitude');
  if (latitude != null && longitude != null && json['startPosition'] == null) {
    json['startPosition'] = {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': 0,
    };
  }
  return json;
}

String _canonicalAction(String action) => switch (action) {
  'STOP' || 'CREATE_STOP' || 'REGISTER_STOP' => 'START_STOP',
  'RESUME' => 'RESUME_STOP',
  'INCIDENT' || 'CREATE_INCIDENT' => 'REPORT_INCIDENT',
  'ACCEPT_SERVICE' => 'ACCEPT',
  'DEPART_ORIGIN' => 'DEPART_FOR_ORIGIN',
  'ARRIVE_ORIGIN' => 'CONFIRM_ORIGIN',
  'START_SERVICE' => 'START',
  'ARRIVE_DESTINATION' => 'CONFIRM_DESTINATION',
  'FINISH_SERVICE' => 'FINISH',
  'SUSPEND_SERVICE' => 'SUSPEND',
  'VIEW_SUMMARY' => 'SUMMARY',
  _ => action,
};

String _canonicalStatus(String? status) => switch (status) {
  'SCHEDULED' => 'PROGRAMADO',
  'ASSIGNED' => 'ASIGNADO',
  'ACCEPTED' || 'PENDING_START' => 'PENDIENTE_INICIO',
  'MOBILIZING' || 'EN_ROUTE_TO_ORIGIN' => 'EN_CAMINO_AL_ORIGEN',
  'ARRIVED_PICKUP' || 'AVAILABLE' || 'AT_ORIGIN' => 'EN_PUNTO_ORIGEN',
  'STARTED' => 'INICIADO',
  'IN_PROGRESS' || 'IN_TRANSIT' => 'EN_RECORRIDO',
  'STOPPED' => 'EN_PARADA',
  'ARRIVED_DESTINATION' || 'AT_DESTINATION' => 'EN_DESTINO',
  'FINISHED' || 'COMPLETED' => 'FINALIZADO',
  'SUSPENDED' => 'SUSPENDIDO',
  'CANCELLED' ||
  'CANCELED' ||
  'CANCELLED_BY_ENTITY' ||
  'NOT_USED_BY_ENTITY' => 'CANCELADO',
  null => 'PENDIENTE',
  _ => status,
};
