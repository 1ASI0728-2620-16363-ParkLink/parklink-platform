import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../../data/repositories/parking_repository.dart';

class CopilotEntry {
  const CopilotEntry({required this.user, required this.text, this.data});
  final bool user;
  final String text;
  final Map<String, dynamic>? data;
}

class CopilotViewModel extends ChangeNotifier {
  CopilotViewModel(this.repository);
  final ParkingRepository repository;
  final _entries = <CopilotEntry>[];
  final completedConfirmations = <String>{};
  List<CopilotEntry> get entries => List.unmodifiable(_entries);
  Map<String, dynamic>? status;
  Map<String, dynamic>? _lastRequest;
  String? conversationId, error;
  DateTime? start, end;
  double latitude = -12.0464, longitude = -77.0428;
  bool busy = false, disposed = false;
  String? busyConfirmation;

  Future<void> loadStatus() async {
    try { status = await repository.request('GET', '/copilot/status') as Map<String, dynamic>; }
    on Object catch (e) { error = e.toString(); }
    _notify();
  }
  void interval(DateTime? beginning, DateTime? ending) { start = beginning; end = ending; _notify(); }
  Future<void> send(String message) async {
    if (busy || message.trim().isEmpty) return;
    _entries.add(CopilotEntry(user: true, text: message.trim()));
    _lastRequest = {'requestId': const Uuid().v4(), if (conversationId != null) 'conversationId': conversationId, 'message': message.trim(), 'latitude': latitude, 'longitude': longitude, 'radius': 5000, if (start != null && end != null) 'start': start!.toUtc().toIso8601String(), if (start != null && end != null) 'end': end!.toUtc().toIso8601String()};
    await retry();
  }
  Future<void> retry() async {
    if (busy || _lastRequest == null) return;
    busy = true; error = null; _notify();
    try {
      final response = await repository.request('POST', '/copilot/chat', body: _lastRequest, timeout: const Duration(seconds: 55)) as Map<String, dynamic>;
      conversationId = response['conversationId'] as String;
      _entries.add(CopilotEntry(user: false, text: '${response['message']}', data: response));
    } on Object catch (e) { error = e.toString(); }
    finally { busy = false; _notify(); }
  }
  Future<void> propose(String action, String reservationId) async {
    if (busy) return; busy = true; error = null; _notify();
    try {
      final proposal = await repository.request('POST', '/copilot/propose-action', body: {'action': action, 'reservationId': reservationId}) as Map<String, dynamic>;
      _entries.add(CopilotEntry(user: false, text: 'Revisa el resumen. No se ha realizado ninguna operación todavía.', data: {'proposal': proposal}));
    } on Object catch (e) { error = e.toString(); }
    finally { busy = false; _notify(); }
  }
  Future<void> confirm(String id, {bool waitForPayment = false}) async {
    if (busy || completedConfirmations.contains(id)) return;
    busy = true; busyConfirmation = id; error = null; _notify();
    try {
      await repository.request('POST', '/copilot/confirm/$id');
      Map<String, dynamic>? operation;
      for (var i = 0; i < 40; i++) {
        operation = await repository.request('GET', '/copilot/commands/$id') as Map<String, dynamic>;
        if (operation['status'] != 'PENDING') break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (operation?['status'] == 'PENDING') throw ParkingApiException('Solicitud recibida y todavía en proceso. Revisa su estado; no crees una segunda operación.');
      completedConfirmations.add(id);
      if (operation?['status'] == 'FAILED') throw ParkingApiException('${(operation?['result'] as Map?)?['message']}');
      final result = operation!['result'] as Map<String, dynamic>;
      final reservationId = (result['reservationId'] ?? result['id']) as String;
      var reservation = await repository.request('GET', '/reservations/$reservationId') as Map<String, dynamic>;
      if (waitForPayment) {
        for (var i = 0; i < 20 && reservation['status'] == 'PENDING_PAYMENT' && reservation['payment_attempt'] != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          reservation = await repository.request('GET', '/reservations/$reservationId') as Map<String, dynamic>;
        }
      }
      _entries.add(CopilotEntry(user: false, text: switch (reservation['status']) {
        'CONFIRMED' => 'El servidor confirmó tu reserva.',
        'CANCELLED' => 'Reserva cancelada. La devolución, si corresponde, se procesa por separado.',
        'PENDING_PAYMENT' => 'La plaza está retenida. El pago todavía no ha confirmado la reserva.',
        _ => 'Estado verificado con el servidor: ${reservation['status']}.',
      }, data: {'reservations': [reservation]}));
    } on Object catch (e) { error = e.toString(); }
    finally { busy = false; busyConfirmation = null; _notify(); }
  }
  Future<void> refreshReservation(String id) async {
    if (busy) return; busy = true; error = null; _notify();
    try {
      final reservation = await repository.request('GET', '/reservations/$id') as Map<String, dynamic>;
      _entries.add(CopilotEntry(user: false, text: 'Estado actualizado desde el servidor.', data: {'reservations': [reservation]}));
    } on Object catch (e) { error = e.toString(); }
    finally { busy = false; _notify(); }
  }
  void _notify() { if (!disposed) notifyListeners(); }
  @override void dispose() { disposed = true; super.dispose(); }
}
