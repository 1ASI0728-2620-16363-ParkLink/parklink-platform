import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../domain/models/parking_space.dart';

class ParkingApiException implements Exception {
  ParkingApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ParkingRepository extends ChangeNotifier {
  ParkingRepository({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();
  static const baseUrl = String.fromEnvironment(
    'PARKLINK_API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
  final http.Client _client;
  final FlutterSecureStorage _storage;
  String? _token;
  Map<String, dynamic>? user;
  bool get authenticated => _token != null;
  bool get isOwner => (user?['roles'] as List?)?.contains('OWNER') ?? false;

  Future<void> restore() async {
    final raw = await _storage.read(key: 'parklink.session.v1');
    if (raw == null) return;
    try {
      final session = jsonDecode(raw) as Map<String, dynamic>;
      if (DateTime.parse(
        session['expiresAt'] as String,
      ).isBefore(DateTime.now())) {
        await logout();
        return;
      }
      _token = session['token'] as String;
      user = session['user'] as Map<String, dynamic>;
    } on Object {
      await logout();
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? key,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = http.Request(method, uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-Correlation-Id': const Uuid().v4(),
        if (_token != null) 'Authorization': 'Bearer $_token',
        'Idempotency-Key': ?key,
      });
    if (body != null) req.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(req).timeout(timeout),
      ).timeout(timeout);
      final data = jsonDecode(response.body);
      if (response.statusCode == 401 && _token != null) await logout();
      if (response.statusCode >= 400) {
        throw ParkingApiException(
          data is Map
              ? '${data['message']}'
              : 'No se pudo completar la operación.',
        );
      }
      return data;
    } on TimeoutException {
      throw ParkingApiException(
        'La conexión tardó demasiado. Consulta el estado antes de repetir una operación.',
      );
    }
  }

  Future<void> login(String email, String password) async => _save(
    await request(
          'POST',
          '/auth/login',
          body: {'email': email, 'password': password},
        )
        as Map<String, dynamic>,
  );
  Future<void> register(
    String name,
    String email,
    String password,
    bool owner,
  ) async => _save(
    await request(
          'POST',
          '/auth/register',
          body: {
            'name': name,
            'email': email,
            'password': password,
            'owner': owner,
          },
        )
        as Map<String, dynamic>,
  );
  Future<void> _save(Map<String, dynamic> session) async {
    _token = session['token'] as String;
    user = session['user'] as Map<String, dynamic>;
    await _storage.write(
      key: 'parklink.session.v1',
      value: jsonEncode({
        ...session,
        'expiresAt': DateTime.now()
            .add(Duration(seconds: session['expiresIn'] as int))
            .toIso8601String(),
      }),
    );
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    user = null;
    await _storage.delete(key: 'parklink.session.v1');
    notifyListeners();
  }

  Future<List<ParkingSpace>> search(
    double latitude,
    double longitude, {
    String text = '',
    int? maxRate,
    int radius = 1000,
    String? feature,
    DateTime? start,
    DateTime? end,
  }) async {
    final query = Uri(
      queryParameters: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'text': text,
        'radius': '$radius',
        'sort': 'nearest',
        'limit': '100',
        if (maxRate != null) 'maxRate': '$maxRate',
        'feature': ?feature,
        if (start != null) 'start': start.toUtc().toIso8601String(),
        if (end != null) 'end': end.toUtc().toIso8601String(),
      },
    ).query;
    final data =
        await request('GET', '/discovery/search?$query')
            as Map<String, dynamic>;
    return (data['items'] as List)
        .map((v) => ParkingSpace.fromJson(v as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<bool> available(
    ParkingSpace space,
    DateTime start,
    DateTime end,
  ) async {
    final query = Uri(
      queryParameters: {
        'spaceId': space.id,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    ).query;
    final data =
        await request('GET', '/reservations/availability?$query')
            as Map<String, dynamic>;
    return data['available'] == true;
  }

  Future<List<Map<String, dynamic>>> list(String path) async =>
      (await request('GET', path) as List).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> command(
    String kind,
    Map<String, dynamic> payload,
  ) async {
    final storageKey = 'parklink.command.${user?['id']}';
    final fingerprint = jsonEncode({'kind': kind, 'payload': payload});
    final previous = await _storage.read(key: storageKey);
    var state = previous == null
        ? <String, dynamic>{}
        : jsonDecode(previous) as Map<String, dynamic>;
    if (state.isNotEmpty && state['fingerprint'] != fingerprint) {
      throw ParkingApiException(
        'Hay una operación pendiente. Consulta tus reservas antes de iniciar otra.',
      );
    }
    if (state.isEmpty) {
      state = {'fingerprint': fingerprint, 'key': const Uuid().v4()};
      await _storage.write(key: storageKey, value: jsonEncode(state));
    }
    if (state['commandId'] == null) {
      final accepted =
          await request(
                'POST',
                '/reservations/commands/$kind',
                body: payload,
                key: state['key'] as String,
              )
              as Map<String, dynamic>;
      state['commandId'] = accepted['commandId'];
      await _storage.write(key: storageKey, value: jsonEncode(state));
    }
    return _poll(state['commandId'] as String, storageKey);
  }

  Future<Map<String, dynamic>?> resumeCommand() async {
    final key = 'parklink.command.${user?['id']}';
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    final state = jsonDecode(raw) as Map<String, dynamic>;
    if (state['commandId'] == null) {
      throw ParkingApiException(
        'Reintenta la misma operación para recuperar su resultado.',
      );
    }
    return _poll(state['commandId'] as String, key);
  }

  Future<Map<String, dynamic>> _poll(
    String commandId,
    String storageKey,
  ) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final operation =
          await request('GET', '/operations/$commandId')
              as Map<String, dynamic>;
      if (operation['status'] != 'PENDING') {
        await _storage.delete(key: storageKey);
        if (operation['status'] == 'FAILED') {
          throw ParkingApiException(
            '${(operation['result'] as Map)['message']}',
          );
        }
        return operation['result'] as Map<String, dynamic>;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw ParkingApiException(
      'Solicitud recibida. Sigue en proceso; consulta tus reservas.',
    );
  }
}
