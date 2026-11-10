class ServiceSummary {
  const ServiceSummary({
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.stopCount,
    required this.incidentCount,
    required this.averageSpeedMps,
    required this.maximumSpeedMps,
  });

  final String status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? durationSeconds;
  final double? distanceMeters;
  final int stopCount;
  final int incidentCount;
  final double? averageSpeedMps;
  final double? maximumSpeedMps;

  factory ServiceSummary.fromJson(Map<String, dynamic> json) {
    final data = json['summary'] as Map<String, dynamic>;
    final metrics = data['metrics'] as Map<String, dynamic>;
    return ServiceSummary(
      status: data['status'] as String,
      startedAt: _summaryDate(data['startedAt']),
      finishedAt: _summaryDate(data['finishedAt']),
      durationSeconds: (metrics['durationS'] as num?)?.toInt(),
      distanceMeters: (metrics['distanceM'] as num?)?.toDouble(),
      stopCount: (metrics['stopCount'] as num?)?.toInt() ?? 0,
      incidentCount: (metrics['incidentCount'] as num?)?.toInt() ?? 0,
      averageSpeedMps: (metrics['averageSpeedMps'] as num?)?.toDouble(),
      maximumSpeedMps: (metrics['maxSpeedMps'] as num?)?.toDouble(),
    );
  }
}

DateTime? _summaryDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}
