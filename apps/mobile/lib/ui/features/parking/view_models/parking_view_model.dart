import 'package:flutter/foundation.dart';
import '../../../../data/repositories/parking_repository.dart';
import '../../../../domain/models/parking_space.dart';

class ParkingViewModel extends ChangeNotifier {
  ParkingViewModel(this.repository);
  final ParkingRepository repository;
  List<ParkingSpace> spaces = [];
  List<Map<String, dynamic>> records = [];
  Map<String, dynamic>? dashboard;
  double latitude = -12.0464, longitude = -77.0428;
  bool busy = false, disposed = false, mapBusy = false;
  String? error, mapError;
  String text = '';
  int? maxRate;
  String? feature;
  int radius = 5000;
  int _searchGeneration = 0, _recordsGeneration = 0;

  Future<void> run(Future<void> Function() action) async {
    if (busy || disposed) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } on Object {
      error =
          'No pudimos completar la operación. Revisa tu conexión y vuelve a intentarlo.';
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Map requests are independent of account actions and ignore stale responses.
  Future<void> search() async {
    final generation = ++_searchGeneration;
    mapBusy = true;
    mapError = null;
    _notify();
    final start = DateTime.now().toUtc().add(const Duration(minutes: 1));
    try {
      final result = await repository.search(
        latitude,
        longitude,
        text: text,
        maxRate: maxRate,
        feature: feature,
        radius: radius,
        start: start,
        end: start.add(const Duration(hours: 1)),
      );
      if (generation == _searchGeneration && !disposed) spaces = result;
    } on Object {
      if (generation == _searchGeneration && !disposed) {
        spaces = [];
        mapError = 'No pudimos actualizar los estacionamientos.';
      }
    } finally {
      if (generation == _searchGeneration) {
        mapBusy = false;
        _notify();
      }
    }
  }

  Future<void> load(String path) async {
    final generation = ++_recordsGeneration;
    records = [];
    busy = true;
    error = null;
    _notify();
    try {
      final result = await repository.list(path);
      if (generation == _recordsGeneration && !disposed) records = result;
    } on Object {
      if (generation == _recordsGeneration) {
        error = 'No pudimos cargar la información. Inténtalo de nuevo.';
      }
    } finally {
      if (generation == _recordsGeneration) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> metrics() => run(() async {
    dashboard =
        await repository.request('GET', '/owner/dashboard')
            as Map<String, dynamic>;
  });
  void _notify() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    _searchGeneration++;
    _recordsGeneration++;
    super.dispose();
  }
}
