String formatDateTime(
  DateTime value, {
  bool includeYear = false,
  bool includeSeconds = false,
  String separator = ' · ',
}) {
  final local = value.toLocal();
  final date =
      '${_twoDigits(local.day)}/${_twoDigits(local.month)}'
      '${includeYear ? '/${local.year}' : ''}';
  return '$date$separator${formatTime(local, includeSeconds: includeSeconds)}';
}

String formatTime(DateTime value, {bool includeSeconds = false}) {
  final local = value.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}'
      '${includeSeconds ? ':${_twoDigits(local.second)}' : ''}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
