class ServiceStop {
  const ServiceStop({required this.id, this.latitude, this.longitude});

  final String id;
  final double? latitude;
  final double? longitude;

  factory ServiceStop.fromJson(Map<String, dynamic> json) {
    final location = json['startPosition'] as Map<String, dynamic>?;
    return ServiceStop(
      id: json['id'] as String,
      latitude: (location?['latitude'] as num?)?.toDouble(),
      longitude: (location?['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (latitude != null && longitude != null)
      'startPosition': {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': 0,
      },
  };
}
