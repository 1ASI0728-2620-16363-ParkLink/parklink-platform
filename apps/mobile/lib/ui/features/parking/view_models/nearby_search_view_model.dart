import 'package:flutter/foundation.dart';
import '../../../../data/repositories/parking_repository.dart';
import '../../../../data/services/parking_location_service.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../domain/models/parking_space.dart';

enum NearbySearchState { searching, locationRequired, empty, found, error }

class NearbyParkingResult {
  const NearbyParkingResult({
    required this.space,
    required this.start,
    required this.end,
    required this.fromDevice,
  });
  final ParkingSpace space;
  final DateTime start, end;
  final bool fromDevice;
}

class NearbySearchViewModel extends ChangeNotifier {
  NearbySearchViewModel(
    this.repository, {
    ParkingLocationService? locationService,
    required this.mapCenter,
    this.radius = 5000,
    this.maxRate,
    this.feature,
    this.text = '',
  }) : locationService = locationService ?? ParkingLocationService();
  final ParkingRepository repository;
  final ParkingLocationService locationService;
  final LocationPoint mapCenter;
  final int radius;
  final int? maxRate;
  final String? feature;
  final String text;
  NearbySearchState state = NearbySearchState.searching;
  ParkingLocationIssue? locationIssue;
  NearbyParkingResult? result;
  LocationPoint? origin;
  bool fromDevice = true, _disposed = false;
  int _generation = 0;

  Future<void> search({
    bool requestPermission = false,
    bool useMapCenter = false,
  }) async {
    final generation = ++_generation;
    state = NearbySearchState.searching;
    locationIssue = null;
    result = null;
    fromDevice = !useMapCenter;
    _notify();
    try {
      final point = useMapCenter
          ? mapCenter
          : await locationService.current(requestPermission: requestPermission);
      if (_disposed || generation != _generation) return;
      origin = point;
      final start = DateTime.now().toUtc().add(const Duration(minutes: 1));
      final end = start.add(const Duration(hours: 1));
      final candidates = await repository.search(
        point.latitude,
        point.longitude,
        radius: radius,
        maxRate: maxRate,
        feature: feature,
        text: text,
        start: start,
        end: end,
      );
      // Discovery is eventually consistent. Check the selected candidate against
      // Reservation's authoritative snapshot without acquiring a hold.
      for (final space in candidates) {
        if (_disposed || generation != _generation) return;
        final available = await repository.available(space, start, end);
        if (_disposed || generation != _generation) return;
        if (available) {
          result = NearbyParkingResult(
            space: space,
            start: start,
            end: end,
            fromDevice: !useMapCenter,
          );
          state = NearbySearchState.found;
          return;
        }
      }
      state = NearbySearchState.empty;
    } on ParkingLocationException catch (e) {
      if (_disposed || generation != _generation) return;
      locationIssue = e.issue;
      state = NearbySearchState.locationRequired;
    } on Object {
      if (_disposed || generation != _generation) return;
      state = NearbySearchState.error;
    } finally {
      if (generation == _generation) _notify();
    }
  }

  Future<bool> openSettings() => locationService.openSettings(
    locationIssue ?? ParkingLocationIssue.blocked,
  );
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
