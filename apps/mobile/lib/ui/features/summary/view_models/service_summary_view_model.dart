import 'package:flutter/foundation.dart';

import '../../../../data/repositories/service_repository.dart';
import '../../../../domain/models/service_summary.dart';

class ServiceSummaryViewModel extends ChangeNotifier {
  ServiceSummaryViewModel({
    required String serviceId,
    required ServiceRepository serviceRepository,
  }) : _serviceId = serviceId,
       _serviceRepository = serviceRepository;

  final String _serviceId;
  final ServiceRepository _serviceRepository;
  ServiceSummary? _summary;
  String? _error;
  bool _loading = false;

  ServiceSummary? get summary => _summary;
  String? get error => _error;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _summary = await _serviceRepository.summary(_serviceId);
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
