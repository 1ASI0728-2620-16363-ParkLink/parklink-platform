enum AppFailureKind {
  network,
  timeout,
  authentication,
  authorization,
  validation,
  conflict,
  server,
  storage,
  location,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(
    this.message, {
    required this.kind,
    this.retryable = false,
    this.requestId,
  });

  final String message;
  final AppFailureKind kind;
  final bool retryable;
  final String? requestId;

  @override
  String toString() =>
      requestId == null ? message : '$message (ID: $requestId)';
}

class ApiFailure extends AppFailure {
  const ApiFailure(
    super.message, {
    required super.kind,
    super.retryable,
    super.requestId,
  });
}

class SessionExpiredFailure extends AppFailure {
  const SessionExpiredFailure([
    super.message = 'Tu sesión venció. Inicia sesión nuevamente.',
  ]) : super(kind: AppFailureKind.authentication);
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message) : super(kind: AppFailureKind.storage);
}
