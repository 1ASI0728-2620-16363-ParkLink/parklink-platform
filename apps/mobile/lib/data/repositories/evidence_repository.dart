import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/location_point.dart';
import '../services/local_database.dart';
import '../services/session_store.dart';

class EvidenceRepository {
  EvidenceRepository({
    required LocalDatabase localDatabase,
    required SessionStore sessionStore,
    ImagePicker? imagePicker,
  }) : _localDatabase = localDatabase,
       _sessionStore = sessionStore,
       _imagePicker = imagePicker ?? ImagePicker();

  final LocalDatabase _localDatabase;
  final SessionStore _sessionStore;
  final ImagePicker _imagePicker;

  Future<String?> capturePhotoEvidence(
    String serviceId,
    LocationPoint location,
  ) async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 78,
      maxWidth: 1920,
    );
    if (image == null) return null;
    return _persistEvidenceFile(
      sourcePath: image.path,
      serviceId: serviceId,
      mimeType: _mimeType(image.path, fallback: 'image/jpeg'),
      location: location,
    );
  }

  Future<String> _persistEvidenceFile({
    required String sourcePath,
    required String serviceId,
    required String mimeType,
    required LocationPoint location,
  }) async {
    final ownerUserId = _sessionStore.ownerUserId;
    if (ownerUserId == null) throw const SessionExpiredFailure();
    final clientEvidenceId = const Uuid().v4();
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'evidence', ownerUserId));
    await directory.create(recursive: true);
    final extension = p.extension(sourcePath).isEmpty
        ? _extensionForMime(mimeType)
        : p.extension(sourcePath).toLowerCase();
    final target = File(p.join(directory.path, '$clientEvidenceId$extension'));
    await File(sourcePath).copy(target.path);
    final bytes = await target.readAsBytes();
    final capturedAt = location.capturedAt ?? DateTime.now().toUtc();
    await _localDatabase.enqueueEvidence(
      PendingEvidence(
        ownerUserId: ownerUserId,
        clientEvidenceId: clientEvidenceId,
        serviceId: serviceId,
        filePath: target.path,
        mimeType: mimeType,
        sha256: sha256.convert(bytes).toString(),
        capturedAt: capturedAt,
        location: location,
        serverId: null,
      ),
    );
    return clientEvidenceId;
  }

  String _mimeType(String path, {required String fallback}) {
    return switch (p.extension(path).toLowerCase()) {
      '.png' => 'image/png',
      '.heic' || '.heif' => 'image/heic',
      '.webp' => 'image/webp',
      '.jpg' || '.jpeg' => 'image/jpeg',
      _ => fallback,
    };
  }

  String _extensionForMime(String mimeType) => switch (mimeType) {
    'image/png' => '.png',
    'image/heic' => '.heic',
    'image/webp' => '.webp',
    _ => '.jpg',
  };
}
