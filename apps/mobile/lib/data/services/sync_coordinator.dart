import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/transport_service.dart';
import '../repositories/tracking_repository.dart';
import 'api_client.dart';
import 'local_database.dart';
import 'session_store.dart';

class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({
    required ApiClient apiClient,
    required LocalDatabase localDatabase,
    required SessionStore sessionStore,
    required TrackingRepository trackingRepository,
  }) : _apiClient = apiClient,
       _localDatabase = localDatabase,
       _sessionStore = sessionStore,
       _trackingRepository = trackingRepository;

  final ApiClient _apiClient;
  final LocalDatabase _localDatabase;
  final SessionStore _sessionStore;
  final TrackingRepository _trackingRepository;
  Timer? _timer;
  Future<void>? _syncInFlight;
  Future<void>? _directCommandInFlight;
  final Set<String> _commandInFlightIds = <String>{};
  SyncHealth _health = const SyncHealth(
    pendingCount: 0,
    deadLetterCount: 0,
    lastError: null,
  );
  String? _lastError;

  Future<void> Function(LocalTrackingSession session)? onTrackingReady;
  Future<void> Function()? onTrackingClosed;

  SyncHealth get health => _health;
  String? get lastError => _lastError ?? _health.lastError;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(syncNow()),
    );
    unawaited(_refreshHealth());
  }

  Future<void> _refreshHealth() async {
    final owner = _sessionStore.ownerUserId;
    if (owner == null) return;
    _health = await _localDatabase.syncHealth(owner);
    notifyListeners();
  }

  Future<void> syncNow() {
    final existing = _syncInFlight;
    if (existing != null) return existing;
    final directCommand = _directCommandInFlight;
    if (directCommand != null) {
      return directCommand.then((_) => syncNow());
    }
    final future = _runSync();
    _syncInFlight = future;
    notifyListeners();
    return future.whenComplete(() {
      if (identical(_syncInFlight, future)) _syncInFlight = null;
      notifyListeners();
    });
  }

  Future<void> _runSync() async {
    final owner = _sessionStore.ownerUserId;
    if (owner == null || !_sessionStore.hasOperationalSession) return;
    _lastError = null;
    try {
      await _syncCommands(owner, finishOnly: false);
      await _syncPositions(owner);
      await _syncCommands(owner, finishOnly: true);
      await _localDatabase.applyRetention(owner);
      await _applyEvidenceRetention(owner);
    } on SessionExpiredFailure catch (error) {
      _lastError = error.message;
    } on Object catch (error) {
      _lastError = error.toString();
    } finally {
      _health = await _localDatabase.syncHealth(owner);
    }
  }

  Future<void> _applyEvidenceRetention(String ownerUserId) async {
    final files = await _localDatabase.evidenceFilesEligibleForRetention(
      ownerUserId,
    );
    for (final path in files) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      await _localDatabase.deleteRetainedEvidenceRow(ownerUserId, path);
    }
  }

  Future<bool> sendCommandNow(String ownerUserId, String clientEventId) {
    final barrier = _directCommandInFlight ?? _syncInFlight;
    final future = (barrier ?? Future<void>.value()).then(
      (_) => _sendCommandNow(ownerUserId, clientEventId),
    );
    final marker = future.then<void>((_) {}).catchError((Object _) {});
    _directCommandInFlight = marker;
    return future.whenComplete(() {
      if (identical(_directCommandInFlight, marker)) {
        _directCommandInFlight = null;
      }
    });
  }

  Future<bool> _sendCommandNow(String ownerUserId, String clientEventId) async {
    final command = await _localDatabase.command(ownerUserId, clientEventId);
    if (command == null) return false;
    if (!_commandInFlightIds.add(command.clientEventId)) {
      while (_commandInFlightIds.contains(command.clientEventId)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final pending = await _localDatabase.command(ownerUserId, clientEventId);
      final deadLetterError = await _localDatabase.commandDeadLetterError(
        ownerUserId,
        clientEventId,
      );
      if (deadLetterError != null) {
        throw AppFailure(deadLetterError, kind: AppFailureKind.conflict);
      }
      return pending != null;
    }
    try {
      await _sendCommand(command);
      await _refreshHealth();
      return false;
    } on SessionExpiredFailure {
      await _refreshHealth();
      rethrow;
    } on AppFailure catch (error) {
      await _recordCommandFailure(command, error, error.retryable);
      await _refreshHealth();
      if (!error.retryable) rethrow;
      return true;
    } on Object catch (error) {
      await _recordCommandFailure(command, error, true);
      await _refreshHealth();
      return true;
    } finally {
      _commandInFlightIds.remove(command.clientEventId);
    }
  }

  Future<void> _syncCommands(
    String ownerUserId, {
    required bool finishOnly,
  }) async {
    final commands = await _localDatabase.pendingCommands(ownerUserId);
    final blockedServices = <String>{};
    for (final command in commands) {
      if ((command.kind == 'FINISH') != finishOnly) continue;
      if (finishOnly &&
          await _localDatabase.hasUnacknowledgedPositionsForService(
            ownerUserId,
            command.serviceId,
          )) {
        continue;
      }
      if (blockedServices.contains(command.serviceId)) continue;
      if (!_commandInFlightIds.add(command.clientEventId)) continue;
      try {
        await _sendCommand(command);
      } on SessionExpiredFailure {
        rethrow;
      } on AppFailure catch (error) {
        await _recordCommandFailure(command, error, error.retryable);
        blockedServices.add(command.serviceId);
      } on Object catch (error) {
        await _recordCommandFailure(command, error, true);
        blockedServices.add(command.serviceId);
      } finally {
        _commandInFlightIds.remove(command.clientEventId);
      }
    }
  }

  Future<bool> serviceHasUnacknowledgedPositions(
    String ownerUserId,
    String serviceId,
  ) {
    return _localDatabase.hasUnacknowledgedPositionsForService(
      ownerUserId,
      serviceId,
    );
  }

  Future<void> _sendCommand(PendingCommand command) async {
    final evidences = await _localDatabase.evidencesByIds(
      command.ownerUserId,
      command.evidenceIds,
    );
    if (evidences.length != command.evidenceIds.length) {
      throw const StorageFailure(
        'Falta un archivo de evidencia requerido por la operación.',
      );
    }
    final serverEvidenceIds = <String>[];
    for (final evidence in evidences) {
      serverEvidenceIds.add(
        evidence.serverId ?? await _uploadEvidence(command, evidence),
      );
    }
    final payload = Map<String, dynamic>.from(command.payload);
    if (evidences.isNotEmpty) {
      payload['evidenceIds'] = serverEvidenceIds;
    }
    final response = await _apiClient.postJson(command.endpoint, payload);

    LocalTrackingSession? readySession;
    if (command.kind == 'START') {
      final localId = command.payload['clientTrackingSessionId'] as String?;
      if (localId == null) {
        throw const StorageFailure(
          'El comando START no contiene su sesión local.',
        );
      }
      readySession = await _trackingRepository.materializeFromResponse(
        serviceId: command.serviceId,
        localId: localId,
        response: response,
      );
    }

    await _localDatabase.markCommandAcknowledged(
      command.ownerUserId,
      command.clientEventId,
    );
    await _applyServiceResponse(command, response);

    if (readySession != null) {
      try {
        await onTrackingReady?.call(readySession);
      } catch (_) {
        // The command is already accepted by the server. The tracking service
        // exposes the permission/platform failure and startup recovery retries.
      }
    } else if (command.kind == 'FINISH') {
      await _trackingRepository.closeActiveSession();
      await onTrackingClosed?.call();
    }
  }

  Future<String> _uploadEvidence(
    PendingCommand command,
    PendingEvidence evidence,
  ) async {
    final file = File(evidence.filePath);
    if (!await file.exists()) {
      throw const StorageFailure(
        'Falta un archivo de evidencia requerido por la operación.',
      );
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != evidence.sha256) {
      throw const StorageFailure(
        'El archivo de evidencia cambió después de capturarse.',
      );
    }
    final response = await _apiClient.postJson('/evidence', {
      'serviceId': evidence.serviceId,
      'evidenceType': command.kind == 'REPORT_INCIDENT'
          ? 'INCIDENT_PHOTO'
          : 'ATTACHMENT',
      'mimeType': evidence.mimeType,
      'base64Data': base64Encode(bytes),
      'capturedAt': evidence.capturedAt.toUtc().toIso8601String(),
      'location': evidence.location.toCommandJson(),
    });
    final uploaded = response['evidence'];
    final serverId = uploaded is Map<String, dynamic>
        ? uploaded['id'] as String?
        : null;
    if (serverId == null || serverId.isEmpty) {
      throw const ApiFailure(
        'La carga de evidencia no devolvió un identificador.',
        kind: AppFailureKind.validation,
      );
    }
    await _localDatabase.markEvidenceUploaded(
      evidence.ownerUserId,
      evidence.clientEvidenceId,
      serverId: serverId,
    );
    return serverId;
  }

  Future<void> _recordCommandFailure(
    PendingCommand command,
    Object error,
    bool retryable,
  ) async {
    final message = error.toString();
    await _localDatabase.failCommand(command, message, retryable: retryable);
    final evidences = await _localDatabase.evidencesByIds(
      command.ownerUserId,
      command.evidenceIds,
    );
    await _localDatabase.failEvidences(
      evidences.where((evidence) => evidence.serverId == null).toList(),
      message,
      retryable: retryable,
    );
  }

  Future<void> _applyServiceResponse(
    PendingCommand command,
    Map<String, dynamic> response,
  ) async {
    final direct = response['service'] as Map<String, dynamic>?;
    if (direct == null) return;
    final current = await _localDatabase.serviceSnapshot(
      command.ownerUserId,
      command.serviceId,
    );
    final merged = current?.toJson() ?? <String, dynamic>{};
    merged.addAll(direct);
    if (response['trackingSession'] != null) {
      merged['trackingSession'] = response['trackingSession'];
    }
    // Las paradas ya no dejan nada abierto que haya que arrastrar aquí.
    await _localDatabase.upsertServiceSnapshot(
      command.ownerUserId,
      TransportService.fromJson(merged),
    );
  }

  Future<void> _syncPositions(String ownerUserId) async {
    final serverDeviceId = _sessionStore.serverDeviceId;
    if (serverDeviceId == null) {
      throw const AppFailure(
        'El dispositivo no está autorizado. Inicia sesión nuevamente.',
        kind: AppFailureKind.authorization,
      );
    }
    final sessions = await _localDatabase.trackingSessionsWithPendingPositions(
      ownerUserId,
    );
    for (final session in sessions) {
      while (true) {
        final pending = await _localDatabase.pendingPositions(
          ownerUserId,
          session,
          limit: session.policy.batchSize,
        );
        if (pending.isEmpty) break;
        try {
          final response = await _apiClient.postJson(
            '/mobile/tracking-sessions/${session.serverId}/positions/batch',
            {
              'deviceId': serverDeviceId,
              'positions': pending.map((item) => item.toJson()).toList(),
            },
          );
          final accepted = <String>{};
          final duplicates = <String>{};
          final results = response['results'];
          if (results is List) {
            for (final item in results.whereType<Map<String, dynamic>>()) {
              final id = item['clientPositionId'] as String?;
              if (id == null) continue;
              final status = item['status'];
              if (status == 'ACCEPTED') {
                accepted.add(id);
              }
              if (status == 'DUPLICATE') {
                duplicates.add(id);
              }
            }
          }
          final ackSequence = (response['ackSequence'] as num?)?.toInt();
          if (ackSequence == null || (accepted.isEmpty && duplicates.isEmpty)) {
            throw const ApiFailure(
              'El ACK del lote de posiciones está incompleto.',
              kind: AppFailureKind.validation,
            );
          }
          await _localDatabase.acknowledgePositions(ownerUserId, {
            ...accepted,
            ...duplicates,
          });
          await _applyTrackingResponse(
            ownerUserId,
            session.serviceId,
            response,
          );
        } on ApiFailure catch (error) {
          await _localDatabase.failPositions(
            ownerUserId,
            pending,
            error.toString(),
            retryable: error.retryable,
          );
          break;
        } on Object catch (error) {
          await _localDatabase.failPositions(
            ownerUserId,
            pending,
            error.toString(),
            retryable: true,
          );
          break;
        }
      }
    }
  }

  Future<void> _applyTrackingResponse(
    String ownerUserId,
    String serviceId,
    Map<String, dynamic> response,
  ) async {
    final current = await _localDatabase.serviceSnapshot(
      ownerUserId,
      serviceId,
    );
    if (current == null) return;
    final merged = current.toJson();
    if (response['serviceStatus'] != null) {
      merged['currentStatus'] = response['serviceStatus'];
    }
    if (response['statusVersion'] != null) {
      merged['statusVersion'] = response['statusVersion'];
    }
    if (response['allowedActions'] != null) {
      merged['allowedActions'] = response['allowedActions'];
    }
    await _localDatabase.upsertServiceSnapshot(
      ownerUserId,
      TransportService.fromJson(merged),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
