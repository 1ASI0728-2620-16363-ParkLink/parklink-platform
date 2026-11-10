class LocationPoint {
  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.speed,
    this.heading,
    this.altitude,
    this.isMocked = false,
    this.provider = 'unknown',
    this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final double? speed;
  final double? heading;
  final double? altitude;
  final bool isMocked;
  final String provider;
  final DateTime? capturedAt;

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy:
          ((json['accuracyM'] ?? json['accuracy']) as num?)?.toDouble() ?? 0,
      speed: (json['speedMps'] as num?)?.toDouble(),
      heading: (json['headingDeg'] as num?)?.toDouble(),
      altitude: (json['altitudeM'] as num?)?.toDouble(),
      isMocked: json['isMocked'] as bool? ?? false,
      provider: json['provider'] as String? ?? 'unknown',
      capturedAt: json['capturedAt'] is String
          ? DateTime.tryParse(json['capturedAt'] as String)?.toUtc()
          : null,
    );
  }

  static LocationPoint? tryParse(Object? raw) {
    try {
      if (raw is Map<String, dynamic>) return LocationPoint.fromJson(raw);
    } catch (_) {
      return null;
    }
    return null;
  }

  static List<LocationPoint> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(tryParse).whereType<LocationPoint>().toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracyM': accuracy,
      'speedMps': speed,
      'headingDeg': heading,
      'altitudeM': altitude,
      'isMocked': isMocked,
      'provider': provider,
      'capturedAt': (capturedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
  }

  Map<String, dynamic> toCommandJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy.isFinite ? accuracy.clamp(0, 10000).toDouble() : 0.0,
    'isMocked': isMocked,
  };
}
