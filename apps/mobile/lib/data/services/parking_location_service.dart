import 'dart:async';

import 'package:geolocator/geolocator.dart';
import '../../domain/models/location_point.dart';

enum ParkingLocationIssue { permission, blocked, disabled, unavailable }

class ParkingLocationException implements Exception {
  const ParkingLocationException(this.issue);
  final ParkingLocationIssue issue;
}

/// One-time foreground positioning; never starts background tracking.
class ParkingLocationService {
  Future<LocationPoint> current({bool requestPermission = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ParkingLocationException(ParkingLocationIssue.disabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const ParkingLocationException(ParkingLocationIssue.blocked);
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const ParkingLocationException(ParkingLocationIssue.permission);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        capturedAt: position.timestamp,
      );
    } on ParkingLocationException {
      rethrow;
    } on LocationServiceDisabledException {
      throw const ParkingLocationException(ParkingLocationIssue.disabled);
    } on PermissionDeniedException {
      throw const ParkingLocationException(ParkingLocationIssue.permission);
    } on Object {
      throw const ParkingLocationException(ParkingLocationIssue.unavailable);
    }
  }

  Future<bool> openSettings(ParkingLocationIssue issue) async {
    try {
      return await (issue == ParkingLocationIssue.disabled
          ? Geolocator.openLocationSettings()
          : Geolocator.openAppSettings());
    } on Object {
      return false;
    }
  }
}
