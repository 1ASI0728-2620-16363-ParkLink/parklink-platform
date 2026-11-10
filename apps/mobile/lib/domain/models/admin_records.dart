import 'location_point.dart';

class DriverRecord {
  const DriverRecord({
    required this.id,
    required this.fullName,
    required this.documentNumber,
    required this.status,
    this.phone,
    this.availabilityStatus = 'NO_DISPONIBLE',
    this.reservationOwner,
    this.reservationId,
    this.vehicleId,
    this.vehicleModel,
    this.vehiclePlate,
  });

  final String id;
  final String fullName;
  final String documentNumber;
  final String? phone;
  final String status;
  final String availabilityStatus;
  final String? reservationOwner;
  final String? reservationId;
  final String? vehicleId;
  final String? vehicleModel;
  final String? vehiclePlate;

  bool get isAvailableForReservation =>
      normalizedAvailabilityStatus == 'DISPONIBLE';

  String get normalizedAvailabilityStatus =>
      _availabilityStatus(availabilityStatus);

  String get availabilityLabel => switch (normalizedAvailabilityStatus) {
    'DISPONIBLE' => 'Disponible',
    'RESERVADO' => 'Reservado',
    'ASIGNADO' => 'Asignado',
    'EN_SERVICIO' => 'En servicio',
    _ => 'No disponible',
  };

  factory DriverRecord.fromJson(Map<String, dynamic> json) {
    final availability = _recordMap(json['availability']);
    final reservation =
        _recordMap(json['reservation']) ??
        _recordMap(availability?['reservation']);
    final reservationOwner =
        _recordMap(json['reservationOwner']) ??
        _recordMap(reservation?['owner']) ??
        _recordMap(availability?['reservationOwner']);
    final vehicle =
        _recordMap(json['vehicle']) ??
        _recordMap(json['assignedVehicle']) ??
        _recordMap(availability?['vehicle']);
    final rawAvailability =
        json['availabilityStatus'] ??
        availability?['status'] ??
        json['driverAvailabilityStatus'] ??
        reservation?['availabilityStatus'] ??
        (reservation?['id'] != null ? 'RESERVADO' : null) ??
        (json['available'] is bool
            ? ((json['available'] as bool) ? 'DISPONIBLE' : 'NO_DISPONIBLE')
            : null) ??
        (_isAvailabilityValue(json['status']) ? json['status'] : null);
    return DriverRecord(
      id: _recordString(json['id']) ?? '',
      fullName: _recordString(json['fullName'] ?? json['name']) ?? 'Conductor',
      documentNumber: _recordString(json['documentNumber']) ?? '',
      phone: _recordString(json['phone']),
      status: _recordString(json['status']) ?? 'UNKNOWN',
      availabilityStatus: _availabilityStatus(rawAvailability),
      reservationOwner: _recordString(
        json['reservationOwnerName'] ??
            (json['reservationOwner'] is String
                ? json['reservationOwner']
                : null) ??
            reservationOwner?['fullName'] ??
            reservationOwner?['name'] ??
            reservationOwner?['id'] ??
            reservation?['ownerName'],
      ),
      reservationId: _recordString(json['reservationId'] ?? reservation?['id']),
      vehicleId: _recordString(json['vehicleId'] ?? vehicle?['id']),
      vehicleModel: _recordString(json['vehicleModel'] ?? vehicle?['model']),
      vehiclePlate: _recordString(json['vehiclePlate'] ?? vehicle?['plate']),
    );
  }

  DriverRecord copyWith({
    String? availabilityStatus,
    String? reservationOwner,
    String? reservationId,
    String? vehicleId,
    String? vehicleModel,
    String? vehiclePlate,
  }) {
    return DriverRecord(
      id: id,
      fullName: fullName,
      documentNumber: documentNumber,
      phone: phone,
      status: status,
      availabilityStatus: availabilityStatus ?? this.availabilityStatus,
      reservationOwner: reservationOwner ?? this.reservationOwner,
      reservationId: reservationId ?? this.reservationId,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
    );
  }
}

class DriverReservation {
  const DriverReservation({
    required this.id,
    required this.serviceId,
    required this.driverId,
    required this.status,
    this.vehicleId,
    this.vehicleModel,
    this.vehiclePlate,
    this.owner,
    this.driver,
  });

  final String id;
  final String serviceId;
  final String driverId;
  final String status;
  final String? vehicleId;
  final String? vehicleModel;
  final String? vehiclePlate;
  final String? owner;
  final DriverRecord? driver;

  bool get confirmed =>
      id.isNotEmpty &&
      const {
        'RESERVADO',
        'RESERVED',
        'CONFIRMED',
        'ACTIVE',
      }.contains(status.trim().toUpperCase());

  factory DriverReservation.fromJson(
    Map<String, dynamic> json, {
    required String fallbackServiceId,
    required String fallbackDriverId,
    DriverRecord? fallbackDriver,
  }) {
    final reservation = _recordMap(json['reservation']) ?? json;
    final driverJson =
        _recordMap(json['driver']) ?? _recordMap(reservation['driver']);
    final vehicle =
        _recordMap(json['vehicle']) ?? _recordMap(reservation['vehicle']);
    final driver = driverJson == null
        ? fallbackDriver
        : DriverRecord.fromJson(driverJson);
    return DriverReservation(
      id:
          _recordString(reservation['id'] ?? reservation['reservationId']) ??
          '',
      serviceId: _recordString(reservation['serviceId']) ?? fallbackServiceId,
      driverId:
          _recordString(reservation['driverId'] ?? driver?.id) ??
          fallbackDriverId,
      status:
          _recordString(reservation['status'] ?? json['status']) ?? 'RESERVADO',
      vehicleId: _recordString(
        reservation['vehicleId'] ??
            json['vehicleId'] ??
            vehicle?['id'] ??
            driver?.vehicleId,
      ),
      vehicleModel: _recordString(
        reservation['vehicleModel'] ??
            json['vehicleModel'] ??
            vehicle?['model'] ??
            driver?.vehicleModel,
      ),
      vehiclePlate: _recordString(
        reservation['vehiclePlate'] ??
            json['vehiclePlate'] ??
            vehicle?['plate'] ??
            driver?.vehiclePlate,
      ),
      owner: _recordString(
        reservation['ownerName'] ??
            _recordMap(reservation['owner'])?['fullName'] ??
            _recordMap(reservation['owner'])?['id'] ??
            driver?.reservationOwner,
      ),
      driver: driver,
    );
  }
}

class VehicleRecord {
  const VehicleRecord({
    required this.id,
    required this.plate,
    required this.model,
    required this.status,
  });

  final String id;
  final String plate;
  final String? model;
  final String status;

  factory VehicleRecord.fromJson(Map<String, dynamic> json) {
    return VehicleRecord(
      id: json['id'] as String,
      plate: json['plate'] as String,
      model: json['model'] as String?,
      status: json['status'] as String,
    );
  }
}

class InvitationRecord {
  const InvitationRecord({
    required this.id,
    required this.email,
    required this.driverName,
    required this.status,
    required this.invitationCode,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String? driverName;
  final String status;
  final String invitationCode;
  final DateTime createdAt;

  factory InvitationRecord.fromJson(Map<String, dynamic> json) {
    return InvitationRecord(
      id: json['id'] as String,
      email: json['email'] as String,
      driverName: json['driverName'] as String?,
      status: json['status'] as String,
      invitationCode: json['invitationCode'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class LiveVehicleRecord {
  const LiveVehicleRecord({
    required this.vehicleId,
    required this.vehiclePlate,
    required this.driverId,
    required this.driverName,
    required this.serviceId,
    required this.serviceCode,
    required this.status,
    required this.startedAt,
    required this.capturedAt,
    required this.speedMps,
    required this.headingDeg,
    required this.currentLocation,
    required this.actualRoute,
  });

  final String vehicleId;
  final String vehiclePlate;
  final String? driverId;
  final String? driverName;
  final String? serviceId;
  final String? serviceCode;
  final String status;
  final DateTime? startedAt;
  final DateTime? capturedAt;
  final double? speedMps;
  final double? headingDeg;
  final LocationPoint? currentLocation;
  final List<LocationPoint> actualRoute;

  bool get isStale =>
      capturedAt == null ||
      DateTime.now().toUtc().difference(capturedAt!).inSeconds > 120;

  factory LiveVehicleRecord.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>?;
    final service = json['service'] as Map<String, dynamic>?;
    final location = json['latitude'] == null
        ? null
        : LocationPoint.tryParse(json);
    return LiveVehicleRecord(
      vehicleId: json['vehicleId'] as String,
      vehiclePlate: json['plate'] as String,
      driverId: driver?['id'] as String?,
      driverName: driver?['fullName'] as String?,
      serviceId: json['serviceId'] as String?,
      serviceCode: service?['code'] as String?,
      status: json['serviceStatus'] as String,
      startedAt: _recordDate(json['startedAt']),
      capturedAt: _recordDate(json['capturedAt']),
      speedMps: (json['speedMps'] as num?)?.toDouble(),
      headingDeg: (json['headingDeg'] as num?)?.toDouble(),
      currentLocation: location,
      actualRoute: LocationPoint.listFrom(json['actualRoute']),
    );
  }
}

class DriverLiveLocation {
  const DriverLiveLocation({
    required this.driverId,
    required this.driverName,
    required this.available,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.heading,
    required this.speed,
    required this.capturedAt,
    required this.stale,
  });

  final String driverId;
  final String driverName;
  final bool available;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? heading;
  final double? speed;
  final DateTime? capturedAt;
  final bool stale;

  bool get hasPosition => latitude != null && longitude != null;

  factory DriverLiveLocation.fromJson(
    Map<String, dynamic> json, {
    DriverLiveLocation? previous,
  }) {
    final eventData = json['data'];
    final event = eventData is Map<String, dynamic>;
    final Map<String, dynamic> payload = event ? eventData : json;
    final latestLocation = payload['latestLocation'];
    final location = LocationPoint.tryParse(
      latestLocation is Map<String, dynamic> ? latestLocation : payload,
    );
    final driverId = (payload['driverId'] as String?) ?? previous?.driverId;
    if (driverId == null || driverId.isEmpty) {
      throw const FormatException('Driver live event without driver id.');
    }
    final capturedAt =
        location?.capturedAt ??
        _recordDate(event ? json['occurredAt'] : payload['updatedAt']) ??
        previous?.capturedAt;
    final stale =
        capturedAt == null ||
        DateTime.now().toUtc().difference(capturedAt).inSeconds > 120;

    return DriverLiveLocation(
      driverId: driverId,
      driverName:
          (payload['fullName'] as String?) ?? previous?.driverName ?? '',
      available:
          (payload['available'] as bool?) ?? previous?.available ?? false,
      latitude: location?.latitude ?? previous?.latitude,
      longitude: location?.longitude ?? previous?.longitude,
      accuracy: location?.accuracy ?? previous?.accuracy,
      heading:
          location?.heading ??
          (payload['headingDeg'] as num?)?.toDouble() ??
          previous?.heading,
      speed:
          location?.speed ??
          (payload['speedMps'] as num?)?.toDouble() ??
          previous?.speed,
      capturedAt: capturedAt,
      stale: stale,
    );
  }

  static DriverLiveLocation? tryParse(
    Map<String, dynamic> json, {
    DriverLiveLocation? previous,
  }) {
    try {
      return DriverLiveLocation.fromJson(json, previous: previous);
    } catch (_) {
      return null;
    }
  }
}

DateTime? _recordDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

Map<String, dynamic>? _recordMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

String? _recordString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

bool _isAvailabilityValue(Object? value) {
  if (value == null) return false;
  return const {
    'DISPONIBLE',
    'AVAILABLE',
    'RESERVADO',
    'RESERVED',
    'ASIGNADO',
    'ASSIGNED',
    'EN_SERVICIO',
    'IN_SERVICE',
    'NO_DISPONIBLE',
    'UNAVAILABLE',
  }.contains(_availabilityStatus(value));
}

String _availabilityStatus(Object? value) {
  final normalized = (value ?? '')
      .toString()
      .trim()
      .toUpperCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return switch (normalized) {
    'AVAILABLE' => 'DISPONIBLE',
    'RESERVED' => 'RESERVADO',
    'ASSIGNED' => 'ASIGNADO',
    'IN_SERVICE' || 'ENSERVICIO' => 'EN_SERVICIO',
    'UNAVAILABLE' || 'INACTIVE' || '' => 'NO_DISPONIBLE',
    _ => normalized,
  };
}
