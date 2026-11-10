import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../data/repositories/auth_repository.dart';

class LoginViewModel extends ChangeNotifier {
  LoginViewModel({AuthRepository? authRepository, Future<void> Function(String, String)? loginAction})
    : assert(authRepository != null || loginAction != null),
      _loginAction = loginAction ?? authRepository!.login;

  final Future<void> Function(String, String) _loginAction;

  bool _isLoading = false;
  bool _disposed = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<bool> login(String email, String password) async {
    final emailOrUsername = email.trim();
    if (emailOrUsername.isEmpty && password.isEmpty) {
      _errorMessage = 'Completa todos los campos';
      _notify();
      return false;
    }
    if (emailOrUsername.isEmpty) {
      _errorMessage = 'Ingresa tu correo o usuario';
      _notify();
      return false;
    }
    if (password.isEmpty) {
      _errorMessage = 'Ingresa tu contraseña';
      _notify();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _notify();
    try {
      await _loginAction(emailOrUsername, password);
      return true;
    } catch (error) {
      if (error is AppFailure) {
        _errorMessage = switch (error.kind) {
          AppFailureKind.authentication => 'Credenciales inválidas',
          AppFailureKind.authorization =>
            'No tienes permiso para acceder con esta cuenta',
          AppFailureKind.validation => 'Revisa los campos e intenta nuevamente',
          _ => error.message,
        };
      } else {
        _errorMessage = 'No se pudo iniciar sesión. Intenta nuevamente';
      }
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
