import 'location_point.dart';

class TrackingPosition {
  const TrackingPosition({
    required this.clientPositionId,
    required this.sequence,
    required this.location,
  });

  final String clientPositionId;
  final int sequence;
  final LocationPoint location;

  Map<String, dynamic> toJson() => {
    'clientPositionId': clientPositionId,
    'sequence': sequence,
    'capturedAt': (location.capturedAt ?? DateTime.now().toUtc())
        .toUtc()
        .toIso8601String(),
    'latitude': location.latitude,
    'longitude': location.longitude,
    'accuracyM': location.accuracy.isFinite
        ? location.accuracy.clamp(0, 10000).toDouble()
        : 0.0,
    if (location.speed case final speed?
        when speed.isFinite && speed >= 0 && speed <= 150)
      'speedMps': speed,
    if (location.heading case final heading?
        when heading.isFinite && heading >= 0 && heading <= 360)
      'headingDeg': heading,
    if (location.altitude case final altitude?
        when altitude.isFinite && altitude >= -1000 && altitude <= 20000)
      'altitudeM': altitude,
    'isMocked': location.isMocked,
    if (location.provider.trim().isNotEmpty &&
        location.provider.trim().length <= 40)
      'provider': location.provider.trim(),
    'source': 'PHONE_APP',
  };
}
