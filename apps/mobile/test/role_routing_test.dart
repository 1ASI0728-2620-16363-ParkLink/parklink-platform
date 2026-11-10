import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/app.dart';
import 'package:mobile_driver/core/config/app_environment.dart';

void main() {
  group('roleRoute', () {
    test('CLIENT opens the client shell, never the driver flow', () {
      expect(roleRoute('CLIENT'), RoleRoute.client);
      expect(roleRoute('CLIENT'), isNot(RoleRoute.driver));
      expect(roleRoute('CLIENT'), isNot(RoleRoute.unsupported));
    });

    test('DRIVER still routes to the driver flow', () {
      expect(roleRoute('DRIVER'), RoleRoute.driver);
    });

    test('unknown or missing roles do not fall into the driver flow', () {
      expect(roleRoute(null), RoleRoute.unsupported);
      expect(roleRoute('OPERATOR'), RoleRoute.unsupported);
      expect(roleRoute(''), RoleRoute.unsupported);
    });

    test('ADMIN, COORDINATOR and VIEWER follow the admin build flag', () {
      final expected = AppEnvironment.enableAdmin
          ? RoleRoute.admin
          : RoleRoute.adminUnavailable;
      expect(roleRoute('ADMIN'), expected);
      expect(roleRoute('COORDINATOR'), expected);
      expect(roleRoute('VIEWER'), expected);
    });
  });
}
