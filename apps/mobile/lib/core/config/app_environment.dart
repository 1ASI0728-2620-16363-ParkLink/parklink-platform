import 'package:flutter/foundation.dart';

class AppEnvironment {
  AppEnvironment._();

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.centinella.tech/api',
  );

  static const enableAdmin = bool.fromEnvironment(
    'ENABLE_ADMIN',
    defaultValue: true,
  );

  static Uri apiBaseUri() {
    final value = _configuredApiBaseUrl.trim();
    if (value.isEmpty) {
      throw StateError('API_BASE_URL es obligatoria.');
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL no es una URL absoluta válida.');
    }
    if (kReleaseMode && uri.scheme != 'https') {
      throw StateError('API_BASE_URL debe usar HTTPS en release.');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw StateError('API_BASE_URL debe usar HTTP o HTTPS.');
    }

    var path = uri.path.replaceFirst(RegExp(r'/$'), '');
    if (path.isEmpty) path = '/api';
    if (!path.endsWith('/api')) {
      throw StateError('API_BASE_URL debe terminar en /api.');
    }
    return uri.replace(path: path, query: null, fragment: null);
  }
}
