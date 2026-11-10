import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/data/services/session_store.dart';
import 'package:mobile_driver/domain/models/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'restaura una sesión antigua vencida por el límite local de 12 horas',
    () async {
      final now = DateTime.now().toUtc();
      FlutterSecureStorage.setMockInitialValues({
        'secure_access_token': 'access',
        'secure_refresh_token': 'refresh',
        'secure_access_expires_at': now
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'secure_absolute_expires_at': now
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        'secure_session_user': jsonEncode(_user),
      });

      final store = await SessionStore.create();

      expect(store.hasSession, isTrue);
      expect(store.refreshToken, 'refresh');
    },
  );

  test('descarta una sesión corrupta sin romper el arranque', () async {
    FlutterSecureStorage.setMockInitialValues({
      'secure_access_token': 'access',
      'secure_refresh_token': 'refresh',
      'secure_session_user': '{invalid-json',
    });

    final store = await SessionStore.create();

    expect(store.hasSession, isFalse);
    expect(store.user, isNull);
  });

  test('usa la expiración de refresh informada por el backend', () {
    final before = DateTime.now().toUtc();
    final session = AuthSession.fromJson({
      'tokens': {
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'expiresIn': 3600,
        'refreshExpiresIn': 120,
      },
      'user': _user,
    });

    final lifetime = session.absoluteExpiresAt.difference(before).inSeconds;
    expect(lifetime, inInclusiveRange(119, 121));
  });
}

const _user = {
  'id': 'user-1',
  'email': 'driver@example.com',
  'fullName': 'Conductor Prueba',
  'role': 'DRIVER',
  'driverId': 'driver-1',
};
