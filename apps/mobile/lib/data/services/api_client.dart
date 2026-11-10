import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/config/app_environment.dart';
import '../../core/errors/app_failure.dart';
import 'session_store.dart';

class ApiClient {
  ApiClient({
    required SessionStore sessionStore,
    http.Client? client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 20),
  }) : _sessionStore = sessionStore,
       _client = client ?? http.Client(),
       _baseUri = baseUri ?? AppEnvironment.apiBaseUri();

  final SessionStore _sessionStore;
  final http.Client _client;
  final Uri _baseUri;
  final Duration timeout;
  Future<void>? _refreshInFlight;

  Future<Map<String, dynamic>> getJson(
    String path, {
    bool authenticated = true,
  }) {
    return _requestJson('GET', path, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) {
    return _requestJson('POST', path, body: body, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) {
    return _requestJson(
      'PATCH',
      path,
      body: body,
      authenticated: authenticated,
    );
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) {
    return _requestJson('PUT', path, body: body, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    bool authenticated = true,
  }) {
    return _requestJson('DELETE', path, authenticated: authenticated);
  }

  Stream<Map<String, dynamic>> streamSseJson(String path) async* {
    await _prepareAuthentication(authenticated: true);
    final requestId = const Uuid().v4();

    Future<http.StreamedResponse> send() {
      final request = http.Request('GET', _uri(path));
      request.headers.addAll(
        _headers(requestId: requestId, accept: 'text/event-stream'),
      );
      request.headers['cache-control'] = 'no-cache';
      return _client.send(request).timeout(timeout);
    }

    try {
      var response = await send();
      if (response.statusCode == 401) {
        await response.stream.drain<void>();
        await _refreshCoordinated();
        response = await send();
        if (response.statusCode == 401) {
          await response.stream.drain<void>();
          await _sessionStore.clear();
          throw const SessionExpiredFailure();
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _decodeObject(await http.Response.fromStream(response), requestId);
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      yield* _decodeServerSentEvents(lines);
    } on AppFailure {
      rethrow;
    } on TimeoutException {
      throw ApiFailure(
        'La conexión en vivo tardó demasiado.',
        kind: AppFailureKind.timeout,
        retryable: true,
        requestId: requestId,
      );
    } on SocketException catch (error) {
      throw _networkFailure(error, requestId);
    } on http.ClientException catch (error) {
      throw _networkFailure(error, requestId);
    } on FormatException {
      throw ApiFailure(
        'El servidor envió un evento en vivo inválido.',
        kind: AppFailureKind.validation,
        requestId: requestId,
      );
    }
  }

  Future<Uint8List> getBytes(String path, {bool authenticated = true}) async {
    await _prepareAuthentication(authenticated: authenticated);
    final requestId = const Uuid().v4();

    Future<http.Response> send() => _client
        .get(
          _uri(path),
          headers: _headers(requestId: requestId, accept: 'application/pdf'),
        )
        .timeout(timeout);

    try {
      var response = await send();
      if (response.statusCode == 401 &&
          authenticated &&
          path != '/auth/refresh') {
        await _refreshCoordinated();
        response = await send();
        if (response.statusCode == 401) {
          await _sessionStore.clear();
          throw const SessionExpiredFailure();
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      return _throwHttpFailure(response, requestId);
    } on AppFailure {
      rethrow;
    } on TimeoutException {
      throw ApiFailure(
        'La descarga tardó demasiado. Intenta nuevamente.',
        kind: AppFailureKind.timeout,
        retryable: true,
        requestId: requestId,
      );
    } on SocketException catch (error) {
      throw _networkFailure(error, requestId);
    } on http.ClientException catch (error) {
      throw _networkFailure(error, requestId);
    }
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool authenticated,
  }) async {
    await _prepareAuthentication(authenticated: authenticated);
    final requestId = const Uuid().v4();

    Future<http.Response> send() {
      final headers = _headers(requestId: requestId);
      return switch (method) {
        'GET' => _client.get(_uri(path), headers: headers).timeout(timeout),
        'POST' =>
          _client
              .post(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
              .timeout(timeout),
        'PATCH' =>
          _client
              .patch(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
              .timeout(timeout),
        'PUT' =>
          _client
              .put(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
              .timeout(timeout),
        'DELETE' =>
          _client.delete(_uri(path), headers: headers).timeout(timeout),
        _ => throw UnsupportedError('Método HTTP no soportado: $method'),
      };
    }

    try {
      var response = await send();
      if (response.statusCode == 401 &&
          authenticated &&
          path != '/auth/refresh') {
        await _refreshCoordinated();
        response = await send();
        if (response.statusCode == 401) {
          await _sessionStore.clear();
          throw const SessionExpiredFailure();
        }
      }
      return _decodeObject(response, requestId);
    } on AppFailure {
      rethrow;
    } on TimeoutException {
      throw ApiFailure(
        'La solicitud tardó demasiado. Intenta nuevamente.',
        kind: AppFailureKind.timeout,
        retryable: true,
        requestId: requestId,
      );
    } on SocketException catch (error) {
      throw _networkFailure(error, requestId);
    } on http.ClientException catch (error) {
      throw _networkFailure(error, requestId);
    } on FormatException {
      throw ApiFailure(
        'El servidor devolvió una respuesta inválida.',
        kind: AppFailureKind.validation,
        requestId: requestId,
      );
    }
  }

  Future<void> _prepareAuthentication({required bool authenticated}) async {
    if (!authenticated) return;
    if (_sessionStore.isAbsolutelyExpired &&
        _sessionStore.refreshToken != null) {
      await _sessionStore.clear();
      throw const SessionExpiredFailure();
    }
    if (_sessionStore.accessToken != null &&
        _sessionStore.isAccessTokenExpiring) {
      await _refreshCoordinated();
    }
  }

  Future<void> _refreshCoordinated() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final refresh = _performRefresh();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
  }

  Future<void> _performRefresh() async {
    if (_sessionStore.isAbsolutelyExpired) {
      await _sessionStore.clear();
      throw const SessionExpiredFailure();
    }
    final token = _sessionStore.refreshToken;
    if (token == null) throw const SessionExpiredFailure();
    final requestId = const Uuid().v4();
    try {
      final response = await _client
          .post(
            _uri('/auth/refresh'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              'x-request-id': requestId,
            },
            body: jsonEncode({'refreshToken': token}),
          )
          .timeout(timeout);
      final body = _decodeObject(response, requestId);
      final tokens = body['tokens'] as Map<String, dynamic>? ?? body;
      final accessToken = tokens['accessToken'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw ApiFailure(
          'La renovación devolvió tokens inválidos.',
          kind: AppFailureKind.validation,
          requestId: requestId,
        );
      }
      await _sessionStore.updateTokens(
        accessToken: accessToken,
        refreshToken: tokens['refreshToken'] as String? ?? token,
        expiresIn: (tokens['expiresIn'] as num?)?.toInt() ?? 900,
        refreshExpiresIn:
            (tokens['refreshExpiresIn'] as num?)?.toInt() ??
            const Duration(days: 30).inSeconds,
      );
    } on ApiFailure catch (error) {
      if (error.kind == AppFailureKind.authentication ||
          error.kind == AppFailureKind.authorization) {
        await _sessionStore.clear();
        throw const SessionExpiredFailure();
      }
      rethrow;
    } on TimeoutException {
      throw ApiFailure(
        'No se pudo renovar la sesión dentro del tiempo esperado.',
        kind: AppFailureKind.timeout,
        retryable: true,
        requestId: requestId,
      );
    } on SocketException catch (error) {
      throw _networkFailure(error, requestId);
    } on http.ClientException catch (error) {
      throw _networkFailure(error, requestId);
    }
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${_baseUri.toString()}$normalizedPath');
  }

  Map<String, String> _headers({
    required String requestId,
    String accept = 'application/json',
  }) {
    final token = _sessionStore.accessToken;
    return {
      'content-type': 'application/json',
      'accept': accept,
      'x-request-id': requestId,
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Never _throwHttpFailure(http.Response response, String requestId) {
    _decodeObject(response, requestId);
    throw StateError('Se esperaba una respuesta HTTP de error.');
  }

  Map<String, dynamic> _decodeObject(http.Response response, String requestId) {
    final responseRequestId = response.headers['x-request-id'] ?? requestId;
    Map<String, dynamic> decoded;
    try {
      final value = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      decoded = value is Map<String, dynamic>
          ? value
          : <String, dynamic>{'data': value};
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      decoded = const <String, dynamic>{};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final error = decoded['error'] as Map<String, dynamic>?;
    final serverMessage =
        (error?['message'] ?? decoded['message']) as String? ??
        'Error HTTP ${response.statusCode}';
    final message = switch (error?['code']) {
      'VALIDATION_ERROR'
          when serverMessage.toLowerCase().contains('request body') =>
        'No pudimos procesar la operación. Actualiza la información e intenta nuevamente.',
      _ => serverMessage,
    };
    final status = response.statusCode;
    final kind = switch (status) {
      401 => AppFailureKind.authentication,
      403 => AppFailureKind.authorization,
      400 || 404 || 422 => AppFailureKind.validation,
      409 => AppFailureKind.conflict,
      >= 500 => AppFailureKind.server,
      _ => AppFailureKind.unknown,
    };
    throw ApiFailure(
      message,
      kind: kind,
      retryable: status == 408 || status == 429 || status >= 500,
      requestId: responseRequestId,
    );
  }

  ApiFailure _networkFailure(Object error, String requestId) => ApiFailure(
    'No se pudo conectar con el servidor. La operación quedó pendiente.',
    kind: AppFailureKind.network,
    retryable: true,
    requestId: requestId,
  );
}

Stream<Map<String, dynamic>> _decodeServerSentEvents(
  Stream<String> lines,
) async* {
  final data = <String>[];
  await for (final line in lines) {
    if (line.isEmpty) {
      final event = _decodeSseData(data);
      data.clear();
      if (event != null) yield event;
      continue;
    }
    if (line.startsWith(':')) continue;
    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    if (field != 'data') continue;
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    data.add(value);
  }
  final event = _decodeSseData(data);
  if (event != null) yield event;
}

Map<String, dynamic>? _decodeSseData(List<String> data) {
  if (data.isEmpty) return null;
  final decoded = jsonDecode(data.join('\n'));
  return decoded is Map<String, dynamic>
      ? decoded
      : <String, dynamic>{'data': decoded};
}
