import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/app_environment.dart';
import 'data/services/session_store.dart';
import 'ui/core/app_scope.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/admin/views/admin_shell_screen.dart';
import 'ui/features/auth/views/login_screen.dart';
import 'ui/features/client/views/client_shell_screen.dart';
import 'ui/features/driver/views/driver_shell_screen.dart';

class TransportControlApp extends StatefulWidget {
  const TransportControlApp({super.key});

  @override
  State<TransportControlApp> createState() => _TransportControlAppState();
}

class _TransportControlAppState extends State<TransportControlApp> {
  Timer? _expiryTimer;
  bool _deviceRegistrationScheduled = false;
  String? _deviceRegistrationError;

  @override
  void initState() {
    super.initState();
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(
        AppScope.of(context, listen: false).sessionStore.expireIfNeeded(),
      );
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionStore = AppScope.of(context, listen: false).sessionStore;
    return ListenableBuilder(
      listenable: sessionStore,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Rutas Control',
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(),
          themeMode: ThemeMode.dark,
          home: _home(sessionStore),
        );
      },
    );
  }

  Widget _home(SessionStore sessionStore) {
    if (!sessionStore.hasSession) return const LoginScreen();
    final branch = roleRoute(sessionStore.user?.role);
    switch (branch) {
      case RoleRoute.admin:
        return const AdminShellScreen();
      case RoleRoute.adminUnavailable:
        return const _RoleUnavailableScreen();
      case RoleRoute.client:
        return const ClientShellScreen();
      case RoleRoute.unsupported:
        return _UnsupportedRoleScreen(role: sessionStore.user?.role);
      case RoleRoute.driver:
        break;
    }
    if (!sessionStore.hasOperationalSession) {
      _scheduleDeviceRegistration();
      return _DeviceRegistrationScreen(
        error: _deviceRegistrationError,
        onRetry: _retryDeviceRegistration,
      );
    }
    return const DriverShellScreen();
  }

  void _scheduleDeviceRegistration() {
    if (_deviceRegistrationScheduled) return;
    _deviceRegistrationError = null;
    _deviceRegistrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_registerDevice());
    });
  }

  void _retryDeviceRegistration() {
    if (_deviceRegistrationScheduled) return;
    setState(() => _deviceRegistrationError = null);
    _scheduleDeviceRegistration();
  }

  Future<void> _registerDevice() async {
    final scope = AppScope.of(context, listen: false);
    try {
      await _bounded(
        () => scope.authRepository.ensureDeviceRegistered(),
        'El registro del dispositivo tardó demasiado. Verifica tu conexión.',
      );
      await _bounded(
        () => scope.backgroundTrackingService.recoverActiveSession(),
        'La recuperación del seguimiento tardó demasiado.',
      );
      await _bounded(
        () => scope.syncCoordinator.syncNow(),
        'La sincronización tardó demasiado.',
      );
    } catch (error) {
      if (mounted && scope.sessionStore.hasSession) {
        setState(() => _deviceRegistrationError = error.toString());
      }
    } finally {
      _deviceRegistrationScheduled = false;
    }
  }

  Future<void> _bounded(Future<void> Function() action, String message) async {
    try {
      await action().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw _RegistrationTimeout(message);
    }
  }
}

class _RegistrationTimeout implements Exception {
  _RegistrationTimeout(this.message);

  final String message;

  @override
  String toString() => message;
}

enum RoleRoute { admin, adminUnavailable, client, driver, unsupported }

@visibleForTesting
RoleRoute roleRoute(String? role) {
  return switch (role) {
    // El observador entra al mismo panel: la propia pantalla le recorta lo que
    // no puede hacer. Duplicar el shell sólo para esconder botones haría que
    // los dos se desincronicen con el tiempo.
    'ADMIN' || 'COORDINATOR' || 'VIEWER' =>
      AppEnvironment.enableAdmin ? RoleRoute.admin : RoleRoute.adminUnavailable,
    'CLIENT' => RoleRoute.client,
    'DRIVER' => RoleRoute.driver,
    _ => RoleRoute.unsupported,
  };
}

class _DeviceRegistrationScreen extends StatelessWidget {
  const _DeviceRegistrationScreen({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error == null)
                  const CircularProgressIndicator()
                else
                  Icon(
                    Icons.phonelink_erase_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                const SizedBox(height: 18),
                Text(
                  error == null
                      ? 'Registrando este dispositivo…'
                      : 'No se pudo registrar este dispositivo',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleUnavailableScreen extends StatelessWidget {
  const _RoleUnavailableScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.badge_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Este build es exclusivo para conductores.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => AppScope.of(
                    context,
                    listen: false,
                  ).authRepository.logout(),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnsupportedRoleScreen extends StatelessWidget {
  const _UnsupportedRoleScreen({this.role});

  final String? role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_accounts_rounded, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Este rol no está soportado en esta aplicación.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Rol: ${role ?? 'desconocido'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => AppScope.of(
                    context,
                    listen: false,
                  ).authRepository.logout(),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
