import 'offline_start_permit.dart';
import 'location_point.dart';
import 'service_stop.dart';
import 'tracking_session.dart';

/// Con tres estados el conductor solo inicia y finaliza. Aceptar, salir hacia
/// el origen y confirmar origen/destino ya no existen: no movian nada que la
/// traza GPS no cuente, y dejaban el servicio atascado si el GPS fallaba.
enum ServiceAction {
  start,
  stop,
  incident,
  finish,
  suspend,
  summary,
}

extension ServiceActionContract on ServiceAction {
  String get contractName => switch (this) {
    ServiceAction.start => 'START',
    ServiceAction.stop => 'START_STOP',
    ServiceAction.incident => 'REPORT_INCIDENT',
    ServiceAction.finish => 'FINISH',
    ServiceAction.suspend => 'SUSPEND',
    ServiceAction.summary => 'SUMMARY',
  };

  String get label => switch (this) {
    ServiceAction.start => 'Iniciar servicio',
    ServiceAction.stop => 'Registrar parada',
    ServiceAction.incident => 'Reportar incidencia',
    ServiceAction.finish => 'Finalizar servicio',
    ServiceAction.suspend => 'Suspender servicio',
    ServiceAction.summary => 'Ver resumen',
  };
}

class ServiceAssignment {
  const ServiceAssignment({
    required this.driverId,
    this.vehicleId,
    this.reservationId,
  });

  final String? driverId;
  final String? vehicleId;
  final String? reservationId;

  factory ServiceAssignment.fromJson(Map<String, dynamic> json) {
    final driver = _map(json['driver']);
    final vehicle = _map(json['vehicle']);
    return ServiceAssignment(
      driverId: _string(json['driverId'] ?? driver?['id']),
      vehicleId: _string(json['vehicleId'] ?? vehicle?['id']),
      reservationId: _string(json['reservationId'] ?? json['reservation_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'driverId': driverId,
    if (vehicleId != null) 'vehicleId': vehicleId,
    if (reservationId != null) 'reservationId': reservationId,
  };
}

class ServiceGeofence {
  const ServiceGeofence({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.maximumAccuracyMeters,
  });

  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final double maximumAccuracyMeters;

  factory ServiceGeofence.fromJson(
    Map<String, dynamic> json, {
    double fallbackMaximumAccuracyMeters = 100,
  }) {
    return ServiceGeofence(
      latitude: _number(json['latitude']),
      longitude: _number(json['longitude']),
      radiusMeters: _number(json['radiusM']) ?? 150,
      maximumAccuracyMeters:
          _number(json['maximumAccuracyMeters']) ??
          fallbackMaximumAccuracyMeters,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'radiusM': radiusMeters,
    'maximumAccuracyMeters': maximumAccuracyMeters,
  };
}

enum DedicatedWaypointType { start, stop, finish }

class DedicatedWaypoint {
  const DedicatedWaypoint({
    required this.id,
    required this.serviceId,
    required this.ordinal,
    required this.type,
    required this.clientWaypointId,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.address,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String serviceId;
  final int ordinal;
  final DedicatedWaypointType type;
  final String clientWaypointId;
  final DateTime capturedAt;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String address;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory DedicatedWaypoint.fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final serviceId = _string(json['serviceId']);
    final clientWaypointId = _string(json['clientWaypointId']);
    final capturedAt = _date(json['capturedAt']);
    final latitude = _number(json['latitude']);
    final longitude = _number(json['longitude']);
    final type = switch (_string(json['type'])?.toUpperCase()) {
      'START' => DedicatedWaypointType.start,
      'STOP' => DedicatedWaypointType.stop,
      'FINISH' => DedicatedWaypointType.finish,
      _ => null,
    };
    if (id == null ||
        serviceId == null ||
        clientWaypointId == null ||
        capturedAt == null ||
        latitude == null ||
        longitude == null ||
        type == null) {
      throw const FormatException('Dedicated waypoint is incomplete.');
    }
    return DedicatedWaypoint(
      id: id,
      serviceId: serviceId,
      ordinal: _integer(json['ordinal']) ?? 0,
      type: type,
      clientWaypointId: clientWaypointId,
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
      accuracy: _number(json['accuracy']),
      address:
          _string(json['address']) ??
          'GPS ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  static DedicatedWaypoint? tryFromJson(Object? raw) {
    try {
      return raw is Map<String, dynamic>
          ? DedicatedWaypoint.fromJson(raw)
          : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'serviceId': serviceId,
    'ordinal': ordinal,
    'type': type.name.toUpperCase(),
    'clientWaypointId': clientWaypointId,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    if (accuracy != null) 'accuracy': accuracy,
    'address': address,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };
}

class TransportService {
  const TransportService({
    required this.id,
    required this.code,
    required this.scheduledAt,
    required this.pickupAddress,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.destinationAddress,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.currentStatus,
    required this.driverName,
    required this.vehiclePlate,
    this.driverPhone,
    this.vehicleId,
    this.vehicleModel,
    this.driverLatitude,
    this.driverLongitude,
    this.driverHeading,
    this.driverLocationCapturedAt,
    this.etaMinutes,
    this.notes,
    this.statusVersion = 0,
    this.allowedActions = const <ServiceAction>{},
    this.assignment,
    this.originGeofence,
    this.destinationGeofence,
    this.offlineStartPermit,
    this.trackingSession,
    this.trackingPolicy = const TrackingPolicy(),
    this.openStop,
    this.hasOpenIncident = false,
    this.actualRoute = const [],
    this.operationMode,
    this.dedicatedTo,
    this.waypoints = const [],
  });

  final String id;
  final String code;
  final DateTime scheduledAt;
  final String pickupAddress;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final String destinationAddress;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final String currentStatus;
  final int statusVersion;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleId;
  final String? vehicleModel;
  final String? vehiclePlate;
  final double? driverLatitude;
  final double? driverLongitude;
  final double? driverHeading;
  final DateTime? driverLocationCapturedAt;
  final int? etaMinutes;
  final String? notes;
  final Set<ServiceAction> allowedActions;
  final ServiceAssignment? assignment;
  final ServiceGeofence? originGeofence;
  final ServiceGeofence? destinationGeofence;
  final OfflineStartPermit? offlineStartPermit;
  final TrackingSession? trackingSession;
  final TrackingPolicy trackingPolicy;
  final ServiceStop? openStop;
  final bool hasOpenIncident;
  final List<LocationPoint> actualRoute;
  final String? operationMode;
  final String? dedicatedTo;
  final List<DedicatedWaypoint> waypoints;

  String get normalizedStatus => currentStatus
      .trim()
      .toUpperCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  bool get isTerminal => const {
    'FINALIZADO',
    'COMPLETADO',
    'COMPLETED',
    'FINISHED',
    'CANCELADO',
    'CANCELLED',
    'RECHAZADO',
    'EXPIRADO',
  }.contains(normalizedStatus);

  bool get isSuspended =>
      const {'SUSPENDIDO', 'SUSPENDED'}.contains(normalizedStatus);

  /// Si la ruta debe dibujarse en el mapa.
  ///
  /// Quedan fuera los viajes terminados y los suspendidos: ninguno de los dos
  /// está rodando, y dibujarlos hace creer que sí.
  bool get isDrawableOnMap => !isTerminal && !isSuspended;

  bool get isDedicated =>
      (operationMode?.trim().toUpperCase().contains('DEDICATED') ?? false) ||
      (dedicatedTo?.trim().isNotEmpty ?? false);

  bool get hasActiveDedicatedDuty {
    if (!isDedicated || isTerminal) return false;
    final ordered = [...waypoints]
      ..sort((first, second) => first.ordinal.compareTo(second.ordinal));
    if (ordered.isNotEmpty) {
      return ordered.last.type != DedicatedWaypointType.finish;
    }
    return trackingSession?.isActive ?? false;
  }

  List<DedicatedWaypoint> get dedicatedStops {
    final stops = waypoints
        .where((waypoint) => waypoint.type == DedicatedWaypointType.stop)
        .toList();
    stops.sort((first, second) => first.ordinal.compareTo(second.ordinal));
    return stops;
  }

  /// El conductor ya arrancó: el viaje está en curso.
  bool get isUnderway => const {
    'INICIADO',
    'STARTED',
    'EN_RECORRIDO',
    'IN_PROGRESS',
    'EN_RUTA_AL_ORIGEN',
    'EN_CAMINO_AL_ORIGEN',
    'EN_RUTA_ORIGEN',
    'MOBILIZING',
    'IN_TRANSIT',
  }.contains(normalizedStatus);

  bool get isSearchingForDriver => const {
    'BUSCANDO_CONDUCTOR',
    'SEARCHING',
    'SEARCHING_FOR_DRIVER',
  }.contains(normalizedStatus);

  bool get hasAssignedDriver =>
      (assignment?.driverId?.isNotEmpty ?? false) ||
      (driverName?.trim().isNotEmpty ?? false);

  bool get hasDriverPosition =>
      driverLatitude != null && driverLongitude != null;

  bool get isDriverLocationStale =>
      driverLocationCapturedAt != null &&
      DateTime.now().toUtc().difference(driverLocationCapturedAt!).inSeconds >
          120;

  factory TransportService.fromJson(Map<String, dynamic> json) {
    final assignmentJson =
        _map(json['assignment']) ??
        ((json['driverId'] != null || json['vehicleId'] != null)
            ? <String, dynamic>{
                'driverId': json['driverId'],
                'vehicleId': json['vehicleId'],
                'reservationId': json['reservationId'],
              }
            : null);
    final driverJson = _map(json['driver']) ?? _map(assignmentJson?['driver']);
    final vehicleJson =
        _map(json['vehicle']) ??
        _map(assignmentJson?['vehicle']) ??
        _map(driverJson?['vehicle']);
    final geofences = _map(json['geofences']);
    final originJson = _map(geofences?['origin']);
    final destinationJson = _map(geofences?['destination']);
    final trackingJson = _map(json['trackingSession']);
    final trackingPolicyJson = _map(json['trackingPolicy']);
    final trackingPolicy = TrackingPolicy.fromJson(trackingPolicyJson);
    final geofenceMaximumAccuracy = _number(
      trackingPolicyJson?['maxGeofenceAccuracyM'],
    );
    final stopJson = _map(json['openStop']);
    final driverLocationJson =
        _map(json['driverLocation']) ??
        _map(json['latestDriverLocation']) ??
        _map(json['latestLocation']) ??
        _map(_map(json['tracking'])?['driverLocation']) ??
        _map(driverJson?['latestLocation']) ??
        _map(driverJson?['location']) ??
        _map(assignmentJson?['driverLocation']);
    final etaJson = _map(json['eta']);
    final rawActions = json['allowedActions'] is List
        ? json['allowedActions'] as List<dynamic>
        : const <dynamic>[];
    final id = _string(json['id'] ?? json['serviceId']);
    if (id == null || id.isEmpty) {
      throw const FormatException('Service without id.');
    }

    return TransportService(
      id: id,
      code: _string(json['code']) ?? id,
      scheduledAt:
          _date(json['scheduledAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      pickupAddress: _string(json['pickupAddress']) ?? 'Sin origen',
      pickupLatitude: _number(
        json['pickupLatitude'] ?? _map(json['pickup'])?['latitude'],
      ),
      pickupLongitude: _number(
        json['pickupLongitude'] ?? _map(json['pickup'])?['longitude'],
      ),
      destinationAddress: _string(json['destinationAddress']) ?? 'Sin destino',
      destinationLatitude: _number(
        json['destinationLatitude'] ?? _map(json['destination'])?['latitude'],
      ),
      destinationLongitude: _number(
        json['destinationLongitude'] ?? _map(json['destination'])?['longitude'],
      ),
      currentStatus:
          _string(
            json['currentStatus'] ?? json['serviceStatus'] ?? json['status'],
          ) ??
          'PROGRAMADO',
      statusVersion: _integer(json['statusVersion']) ?? 0,
      driverName: _string(
        json['driverName'] ??
            driverJson?['fullName'] ??
            driverJson?['name'] ??
            assignmentJson?['driverName'],
      ),
      driverPhone: _string(
        json['driverPhone'] ??
            driverJson?['phone'] ??
            _map(driverJson?['contact'])?['phone'] ??
            assignmentJson?['driverPhone'],
      ),
      vehicleId: _string(
        json['vehicleId'] ?? vehicleJson?['id'] ?? assignmentJson?['vehicleId'],
      ),
      vehicleModel: _string(
        json['vehicleModel'] ??
            vehicleJson?['model'] ??
            assignmentJson?['vehicleModel'],
      ),
      vehiclePlate: _string(
        json['vehiclePlate'] ??
            vehicleJson?['plate'] ??
            assignmentJson?['vehiclePlate'],
      ),
      driverLatitude: _number(
        json['driverLatitude'] ??
            driverLocationJson?['latitude'] ??
            driverLocationJson?['lat'] ??
            driverJson?['latitude'],
      ),
      driverLongitude: _number(
        json['driverLongitude'] ??
            driverLocationJson?['longitude'] ??
            driverLocationJson?['lng'] ??
            driverLocationJson?['lon'] ??
            driverJson?['longitude'],
      ),
      driverHeading: _number(
        json['driverHeading'] ??
            driverLocationJson?['heading'] ??
            driverLocationJson?['headingDeg'],
      ),
      driverLocationCapturedAt: _date(
        json['driverLocationCapturedAt'] ??
            driverLocationJson?['capturedAt'] ??
            driverLocationJson?['updatedAt'],
      ),
      etaMinutes: _integer(
        json['etaMinutes'] ??
            json['estimatedArrivalMinutes'] ??
            assignmentJson?['etaMinutes'] ??
            etaJson?['minutes'],
      ),
      notes: _string(json['notes']),
      allowedActions: rawActions
          .map(_parseAction)
          .whereType<ServiceAction>()
          .toSet(),
      assignment: assignmentJson == null
          ? null
          : ServiceAssignment.fromJson(assignmentJson),
      originGeofence: originJson == null
          ? null
          : ServiceGeofence.fromJson(
              originJson,
              fallbackMaximumAccuracyMeters: geofenceMaximumAccuracy ?? 100,
            ),
      destinationGeofence: destinationJson == null
          ? null
          : ServiceGeofence.fromJson(
              destinationJson,
              fallbackMaximumAccuracyMeters: geofenceMaximumAccuracy ?? 100,
            ),
      offlineStartPermit: json['offlineStartPermit'] == null
          ? null
          : OfflineStartPermit.fromJson(json['offlineStartPermit']),
      trackingSession: trackingJson == null
          ? null
          : TrackingSession.fromJson(
              trackingJson,
              serviceId: id,
              fallbackPolicy: trackingPolicy,
            ),
      trackingPolicy: trackingPolicy,
      openStop: stopJson == null ? null : ServiceStop.fromJson(stopJson),
      hasOpenIncident: json['hasOpenIncident'] as bool? ?? false,
      actualRoute: LocationPoint.listFrom(json['actualRoute']),
      operationMode: _string(json['operationMode']),
      dedicatedTo: _string(json['dedicatedTo']),
      waypoints: (json['waypoints'] as List<dynamic>? ?? const [])
          .map(DedicatedWaypoint.tryFromJson)
          .whereType<DedicatedWaypoint>()
          .toList(),
    );
  }

  static TransportService? tryFromEnvelope(Map<String, dynamic> json) {
    final data = _map(json['data']);
    final raw =
        _map(json['service']) ??
        _map(json['request']) ??
        _map(data?['service']) ??
        _map(data?['request']) ??
        (data != null &&
                (data.containsKey('id') || data.containsKey('serviceId'))
            ? data
            : null) ??
        ((json.containsKey('id') || json.containsKey('serviceId'))
            ? json
            : null);
    if (raw == null) return null;
    try {
      return TransportService.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'scheduledAt': scheduledAt.toIso8601String(),
      'pickupAddress': pickupAddress,
      'pickupLatitude': pickupLatitude,
      'pickupLongitude': pickupLongitude,
      'destinationAddress': destinationAddress,
      'destinationLatitude': destinationLatitude,
      'destinationLongitude': destinationLongitude,
      'currentStatus': currentStatus,
      'statusVersion': statusVersion,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'vehicleId': vehicleId,
      'vehicleModel': vehicleModel,
      'vehiclePlate': vehiclePlate,
      'driverLatitude': driverLatitude,
      'driverLongitude': driverLongitude,
      'driverHeading': driverHeading,
      'driverLocationCapturedAt': driverLocationCapturedAt?.toIso8601String(),
      'etaMinutes': etaMinutes,
      'notes': notes,
      'allowedActions': allowedActions
          .map((action) => action.contractName)
          .toList(),
      'assignment': assignment?.toJson(),
      'geofences': {
        if (originGeofence != null) 'origin': originGeofence!.toJson(),
        if (destinationGeofence != null)
          'destination': destinationGeofence!.toJson(),
      },
      'offlineStartPermit': offlineStartPermit?.toJson(),
      if (trackingSession != null)
        'trackingSession': {
          'id': trackingSession!.id,
          'clientSessionId': trackingSession!.localId,
          'status': trackingSession!.status,
          'lastSequence': trackingSession!.lastSequence,
        },
      'trackingPolicy': trackingPolicy.toJson(),
      if (openStop != null) 'openStop': openStop!.toJson(),
      'hasOpenIncident': hasOpenIncident,
      if (actualRoute.isNotEmpty)
        'actualRoute': actualRoute.map((point) => point.toJson()).toList(),
      if (operationMode != null) 'operationMode': operationMode,
      if (dedicatedTo != null) 'dedicatedTo': dedicatedTo,
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map((waypoint) => waypoint.toJson()).toList(),
    };
  }

  TransportService copyWith({
    OfflineStartPermit? offlineStartPermit,
    List<LocationPoint>? actualRoute,
  }) {
    return TransportService(
      id: id,
      code: code,
      scheduledAt: scheduledAt,
      pickupAddress: pickupAddress,
      pickupLatitude: pickupLatitude,
      pickupLongitude: pickupLongitude,
      destinationAddress: destinationAddress,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
      currentStatus: currentStatus,
      statusVersion: statusVersion,
      driverName: driverName,
      driverPhone: driverPhone,
      vehicleId: vehicleId,
      vehicleModel: vehicleModel,
      vehiclePlate: vehiclePlate,
      driverLatitude: driverLatitude,
      driverLongitude: driverLongitude,
      driverHeading: driverHeading,
      driverLocationCapturedAt: driverLocationCapturedAt,
      etaMinutes: etaMinutes,
      notes: notes,
      allowedActions: allowedActions,
      assignment: assignment,
      originGeofence: originGeofence,
      destinationGeofence: destinationGeofence,
      offlineStartPermit: offlineStartPermit ?? this.offlineStartPermit,
      trackingSession: trackingSession,
      trackingPolicy: trackingPolicy,
      openStop: openStop,
      hasOpenIncident: hasOpenIncident,
      actualRoute: actualRoute ?? this.actualRoute,
      operationMode: operationMode,
      dedicatedTo: dedicatedTo,
      waypoints: waypoints,
    );
  }
}

ServiceAction? _parseAction(dynamic raw) {
  return switch (raw) {
    'START' => ServiceAction.start,
    'START_STOP' => ServiceAction.stop,
    'REPORT_INCIDENT' => ServiceAction.incident,
    'FINISH' => ServiceAction.finish,
    'SUSPEND' => ServiceAction.suspend,
    'SUMMARY' => ServiceAction.summary,
    _ => null,
  };
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _integer(Object? value) {
  if (value is num) return value.round();
  if (value is String) return double.tryParse(value)?.round();
  return null;
}

String? _string(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;
