import 'dart:convert';

import '../../core/errors/app_failure.dart';
import '../../domain/models/location_point.dart';
import '../../domain/models/offline_start_permit.dart';
import '../../domain/models/service_summary.dart';
import '../../domain/models/transport_service.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';
import '../services/session_store.dart';

class ServiceRepository {
  ServiceRepository({
    required ApiClient apiClient,
    required LocalDatabase localDatabase,
    required SessionStore sessionStore,
  }) : _apiClient = apiClient,
       _localDatabase = localDatabase,
       _sessionStore = sessionStore;

  final ApiClient _apiClient;
  final LocalDatabase _localDatabase;
  final SessionStore _sessionStore;
  String? _lastWarning;

  String? get lastWarning => _lastWarning;

  Future<List<TransportService>> assignedServices() async {
    final owner = _owner;
    _lastWarning = null;
    try {
      final response = await _apiClient.getJson('/mobile/services');
      final services = (response['services'] as List<dynamic>? ?? const [])
          .map(
            (json) => TransportService.fromJson(json as Map<String, dynamic>),
          )
          .toList();
      final hydrated = <TransportService>[];
      for (final service in services) {
        final permit = service.offlineStartPermit;
        if (permit != null) {
          await _sessionStore.saveOfflinePermit(
            service.id,
            jsonEncode(permit.toJson()),
          );
        }
        hydrated.add(await _withServerRoute(service));
      }
      await _localDatabase.replaceServiceSnapshots(owner, hydrated);
      return hydrated;
    } on ApiFailure catch (error) {
      if (!error.retryable) rethrow;
      final cached = await _hydratePermits(
        await _localDatabase.serviceSnapshots(owner),
      );
      if (cached.isEmpty) rethrow;
      _lastWarning =
          'Sin conexión: se muestran asignaciones guardadas en el dispositivo.';
      return cached;
    }
  }

  Future<TransportService?> serviceDetail(String serviceId) async {
    final owner = _owner;
    final cachedRaw = await _localDatabase.serviceSnapshot(owner, serviceId);
    final cached = cachedRaw == null ? null : await _hydratePermit(cachedRaw);
    try {
      final services = await assignedServices();
      for (final service in services) {
        if (service.id == serviceId) return service;
      }
      return cached;
    } on ApiFailure catch (error) {
      if (cached != null && error.retryable) return cached;
      rethrow;
    }
  }

  Future<TransportService?> cachedServiceDetail(String serviceId) async {
    final cached = await _localDatabase.serviceSnapshot(_owner, serviceId);
    return cached == null ? null : _hydratePermit(cached);
  }

  Future<DedicatedServiceActionResult> startDedicatedService({
    required String clientWaypointId,
    required LocationPoint location,
    required String address,
  }) {
    return _dedicatedAction(
      endpoint: '/mobile/dedicated-services/start',
      clientWaypointId: clientWaypointId,
      location: location,
      address: address,
    );
  }

  Future<DedicatedServiceActionResult> registerDedicatedStop({
    required TransportService service,
    required String clientWaypointId,
    required LocationPoint location,
    required String address,
  }) {
    return _dedicatedAction(
      endpoint: '/mobile/dedicated-services/${service.id}/stops',
      currentService: service,
      clientWaypointId: clientWaypointId,
      location: location,
      address: address,
    );
  }

  Future<DedicatedServiceActionResult> finishDedicatedService({
    required TransportService service,
    required String clientWaypointId,
    required LocationPoint location,
    required String address,
  }) {
    return _dedicatedAction(
      endpoint: '/mobile/dedicated-services/${service.id}/finish',
      currentService: service,
      clientWaypointId: clientWaypointId,
      location: location,
      address: address,
    );
  }

  Future<DedicatedServiceActionResult> _dedicatedAction({
    required String endpoint,
    required String clientWaypointId,
    required LocationPoint location,
    required String address,
    TransportService? currentService,
  }) async {
    final capturedAt = location.capturedAt?.toUtc() ?? DateTime.now().toUtc();
    final response = await _apiClient.postJson(endpoint, {
      'clientWaypointId': clientWaypointId,
      'capturedAt': capturedAt.toIso8601String(),
      'location': {
        'latitude': location.latitude,
        'longitude': location.longitude,
        if (location.accuracy.isFinite)
          'accuracy': location.accuracy.clamp(0, 10000).toDouble(),
      },
      'address': address.trim(),
    });
    final data = response['data'] as Map<String, dynamic>?;
    Object? field(String key) => response[key] ?? data?[key];
    final rawService = field('service');
    if (rawService is! Map<String, dynamic>) {
      throw const ApiFailure(
        'El servicio dedicado no devolvió los datos del servicio.',
        kind: AppFailureKind.validation,
      );
    }

    final merged = currentService?.toJson() ?? <String, dynamic>{};
    merged.addAll(rawService);
    final assignment = field('assignment');
    final trackingSession = field('trackingSession');
    if (assignment is Map<String, dynamic>) merged['assignment'] = assignment;
    if (trackingSession is Map<String, dynamic>) {
      merged['trackingSession'] = trackingSession;
    }

    final waypoint = DedicatedWaypoint.tryFromJson(field('waypoint'));
    if (waypoint != null) {
      final waypoints = <Map<String, dynamic>>[
        for (final raw in merged['waypoints'] as List<dynamic>? ?? const [])
          if (raw is Map<String, dynamic>) raw,
      ];
      if (!waypoints.any((item) => item['id'] == waypoint.id)) {
        waypoints.add(waypoint.toJson());
      }
      waypoints.sort(
        (first, second) => ((first['ordinal'] as num?)?.toInt() ?? 0).compareTo(
          (second['ordinal'] as num?)?.toInt() ?? 0,
        ),
      );
      merged['waypoints'] = waypoints;
    }

    final service = TransportService.fromJson(merged);
    await _localDatabase.upsertServiceSnapshot(_owner, service);
    return DedicatedServiceActionResult(
      status: field('status')?.toString() ?? 'accepted',
      duplicate: field('duplicate') as bool? ?? false,
      service: service,
      waypoint: waypoint,
    );
  }

  Future<TransportService> _withServerRoute(TransportService service) async {
    if (service.trackingSession?.id == null) return service;

    try {
      final points = <LocationPoint>[];
      final seenCursors = <String>{};
      String? cursor;
      do {
        final query = cursor == null
            ? 'limit=200'
            : 'limit=200&cursor=${Uri.encodeQueryComponent(cursor)}';
        final response = await _apiClient.getJson(
          '/mobile/services/${service.id}/route?$query',
        );
        points.addAll(LocationPoint.listFrom(response['positions']));
        final page = response['page'] as Map<String, dynamic>?;
        final nextCursor = page?['nextCursor'] as String?;
        if (page?['hasMore'] != true || nextCursor == null) break;
        if (!seenCursors.add(nextCursor)) break;
        cursor = nextCursor;
      } while (true);
      return service.copyWith(actualRoute: points);
    } on AppFailure {
      _lastWarning ??=
          'No se pudo recuperar el recorrido confirmado del servidor.';
      return service;
    }
  }

  Future<List<TransportService>> _hydratePermits(
    List<TransportService> services,
  ) async {
    final hydrated = <TransportService>[];
    for (final service in services) {
      hydrated.add(await _hydratePermit(service));
    }
    return hydrated;
  }

  Future<TransportService> _hydratePermit(TransportService service) async {
    if (service.offlineStartPermit != null) return service;
    final raw = await _sessionStore.offlinePermit(service.id);
    if (raw == null) return service;
    try {
      return service.copyWith(
        offlineStartPermit: OfflineStartPermit.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      return service;
    }
  }

  Future<ServiceSummary> summary(String serviceId) async {
    final response = await _apiClient.getJson(
      '/mobile/services/$serviceId/summary',
    );
    return ServiceSummary.fromJson(response);
  }

  String get _owner {
    final owner = _sessionStore.ownerUserId;
    if (owner == null) throw const SessionExpiredFailure();
    return owner;
  }
}

class DedicatedServiceActionResult {
  const DedicatedServiceActionResult({
    required this.status,
    required this.duplicate,
    required this.service,
    required this.waypoint,
  });

  final String status;
  final bool duplicate;
  final TransportService service;
  final DedicatedWaypoint? waypoint;
}
