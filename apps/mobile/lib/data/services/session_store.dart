import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/auth_session.dart';

class SessionStore extends ChangeNotifier {
  SessionStore._({
    required FlutterSecureStorage secureStorage,
    required String installationId,
    required String? accessToken,
    required String? refreshToken,
    required String? serverDeviceId,
    required DateTime? accessExpiresAt,
    required DateTime? absoluteExpiresAt,
    required UserProfile? user,
  }) : _secureStorage = secureStorage,
       _installationId = installationId,
       _accessToken = accessToken,
       _refreshToken = refreshToken,
       _serverDeviceId = serverDeviceId,
       _accessExpiresAt = accessExpiresAt,
       _absoluteExpiresAt = absoluteExpiresAt,
       _user = user;

  static const _accessTokenKey = 'secure_access_token';
  static const _refreshTokenKey = 'secure_refresh_token';
  static const _serverDeviceIdKey = 'secure_server_device_id';
  static const _accessExpiresAtKey = 'secure_access_expires_at';
  static const _absoluteExpiresAtKey = 'secure_absolute_expires_at';
  static const _userKey = 'secure_session_user';
  static const _installationIdKey = 'secure_installation_id';
  static const _legacyTrackingTokenPrefix = 'tracking_token_';
  static const _offlinePermitPrefix = 'offline_permit_';

  final FlutterSecureStorage _secureStorage;
  final String _installationId;

  String? _accessToken;
  String? _refreshToken;
  String? _serverDeviceId;
  DateTime? _accessExpiresAt;
  DateTime? _absoluteExpiresAt;
  UserProfile? _user;

  static Future<SessionStore> create({
    FlutterSecureStorage? secureStorage,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final storage =
        secureStorage ??
        const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );
    var installationId = await storage.read(key: _installationIdKey);
    installationId ??= preferences.getString('installation_id');
    installationId ??= const Uuid().v4();
    await storage.write(key: _installationIdKey, value: installationId);

    // One-time migration from the insecure MVP keys.
    var accessToken = await storage.read(key: _accessTokenKey);
    var refreshToken = await storage.read(key: _refreshTokenKey);
    accessToken ??= preferences.getString('accessToken');
    refreshToken ??= preferences.getString('refreshToken');
    if (accessToken != null) {
      await storage.write(key: _accessTokenKey, value: accessToken);
    }
    if (refreshToken != null) {
      await storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await preferences.remove('accessToken');
    await preferences.remove('refreshToken');

    var userRaw =
        await storage.read(key: _userKey) ??
        preferences.getString('session_user') ??
        preferences.getString('user');
    if (userRaw != null) await storage.write(key: _userKey, value: userRaw);
    await Future.wait([
      preferences.remove('installation_id'),
      preferences.remove('session_user'),
      preferences.remove('user'),
    ]);

    UserProfile? user;
    if (userRaw != null) {
      try {
        final decoded = jsonDecode(userRaw);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        user = UserProfile.fromJson(decoded);
      } catch (_) {
        userRaw = null;
        await storage.delete(key: _userKey);
      }
    }

    final accessExpiresAt = _parseStoredDate(
      await storage.read(key: _accessExpiresAtKey),
    );
    var absoluteExpiresAt = _parseStoredDate(
      await storage.read(key: _absoluteExpiresAtKey),
    );
    final legacyShortExpiry =
        absoluteExpiresAt == null ||
        accessExpiresAt == null ||
        absoluteExpiresAt.difference(accessExpiresAt) <=
            const Duration(days: 1);
    if (accessToken?.isNotEmpty == true &&
        refreshToken?.isNotEmpty == true &&
        user != null &&
        legacyShortExpiry) {
      // Builds viejos imponían un logout local de 12 horas. El refresh endpoint
      // del backend es quien debe decidir si la sesión continúa siendo válida.
      absoluteExpiresAt = DateTime.now().toUtc().add(const Duration(days: 30));
      await storage.write(
        key: _absoluteExpiresAtKey,
        value: absoluteExpiresAt.toIso8601String(),
      );
    }

    final completeSession =
        accessToken?.isNotEmpty == true &&
        refreshToken?.isNotEmpty == true &&
        user != null &&
        absoluteExpiresAt != null;
    if (!completeSession) {
      accessToken = null;
      refreshToken = null;
      user = null;
      absoluteExpiresAt = null;
      await Future.wait([
        storage.delete(key: _accessTokenKey),
        storage.delete(key: _refreshTokenKey),
        storage.delete(key: _serverDeviceIdKey),
        storage.delete(key: _accessExpiresAtKey),
        storage.delete(key: _absoluteExpiresAtKey),
        storage.delete(key: _userKey),
      ]);
    }

    return SessionStore._(
      secureStorage: storage,
      installationId: installationId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      serverDeviceId: completeSession
          ? await storage.read(key: _serverDeviceIdKey)
          : null,
      accessExpiresAt: completeSession ? accessExpiresAt : null,
      absoluteExpiresAt: absoluteExpiresAt,
      user: user,
    );
  }

  bool get hasSession {
    final absolute = _absoluteExpiresAt;
    return _accessToken?.isNotEmpty == true &&
        _refreshToken?.isNotEmpty == true &&
        _user != null &&
        absolute != null &&
        DateTime.now().toUtc().isBefore(absolute);
  }

  bool get hasOperationalSession =>
      hasSession && (_serverDeviceId?.isNotEmpty ?? false);

  bool get isAccessTokenExpiring {
    final expiry = _accessExpiresAt;
    if (expiry == null) return true;
    return !DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 30))
        .isBefore(expiry);
  }

  bool get isAbsolutelyExpired {
    final expiry = _absoluteExpiresAt;
    return expiry == null || !DateTime.now().toUtc().isBefore(expiry);
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get serverDeviceId => _serverDeviceId;
  String get installationId => _installationId;
  UserProfile? get user => _user;
  String? get ownerUserId => _user?.id;

  Future<void> saveSession(AuthSession session) async {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _accessExpiresAt = session.accessExpiresAt;
    _absoluteExpiresAt = session.absoluteExpiresAt;
    _user = session.user;
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: _accessToken),
      _secureStorage.write(key: _refreshTokenKey, value: _refreshToken),
      _secureStorage.write(
        key: _accessExpiresAtKey,
        value: _accessExpiresAt!.toIso8601String(),
      ),
      _secureStorage.write(
        key: _absoluteExpiresAtKey,
        value: _absoluteExpiresAt!.toIso8601String(),
      ),
      _secureStorage.write(
        key: _userKey,
        value: jsonEncode(session.user.toJson()),
      ),
    ]);
    notifyListeners();
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
    required int refreshExpiresIn,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _accessExpiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    _absoluteExpiresAt = DateTime.now().toUtc().add(
      Duration(seconds: refreshExpiresIn),
    );
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: _accessToken),
      _secureStorage.write(key: _refreshTokenKey, value: _refreshToken),
      _secureStorage.write(
        key: _accessExpiresAtKey,
        value: _accessExpiresAt!.toIso8601String(),
      ),
      _secureStorage.write(
        key: _absoluteExpiresAtKey,
        value: _absoluteExpiresAt!.toIso8601String(),
      ),
    ]);
    notifyListeners();
  }

  Future<void> saveServerDeviceId(String value) async {
    _serverDeviceId = value;
    await _secureStorage.write(key: _serverDeviceIdKey, value: value);
    notifyListeners();
  }

  Future<void> saveOfflinePermit(String serviceId, String permitJson) {
    return _secureStorage.write(
      key: '$_offlinePermitPrefix$serviceId',
      value: permitJson,
    );
  }

  Future<String?> offlinePermit(String serviceId) {
    return _secureStorage.read(key: '$_offlinePermitPrefix$serviceId');
  }

  Future<void> clear() async {
    Map<String, String> secureValues = const {};
    try {
      secureValues = await _secureStorage.readAll();
    } catch (_) {
      // Limpiar la sesión en memoria no puede depender de leer claves auxiliares.
    }
    _accessToken = null;
    _refreshToken = null;
    _serverDeviceId = null;
    _accessExpiresAt = null;
    _absoluteExpiresAt = null;
    _user = null;
    notifyListeners();
    await Future.wait(
      [
        _accessTokenKey,
        _refreshTokenKey,
        _serverDeviceIdKey,
        _accessExpiresAtKey,
        _absoluteExpiresAtKey,
        _userKey,
        ...secureValues.keys.where(
          (key) =>
              key.startsWith(_legacyTrackingTokenPrefix) ||
              key.startsWith(_offlinePermitPrefix),
        ),
      ].map((key) async {
        try {
          await _secureStorage.delete(key: key);
        } catch (_) {
          // La sesión ya quedó invalidada en memoria; el borrado es best effort.
        }
      }),
    );
  }

  Future<void> expireIfNeeded() async {
    if ((_accessToken != null || _refreshToken != null || _user != null) &&
        !hasSession) {
      await clear();
    }
  }
}

DateTime? _parseStoredDate(String? value) =>
    value == null ? null : DateTime.tryParse(value)?.toUtc();
