class TrackingPolicy {
  const TrackingPolicy({
    this.intervalSeconds = 15,
    this.distanceFilterMeters = 25,
    this.batchSize = 25,
  });

  final int intervalSeconds;
  final int distanceFilterMeters;
  final int batchSize;

  factory TrackingPolicy.fromJson(Map<String, dynamic>? json) {
    return TrackingPolicy(
      intervalSeconds: ((json?['activeIntervalSeconds'] as num?)?.toInt() ?? 15)
          .clamp(3, 120)
          .toInt(),
      distanceFilterMeters:
          ((json?['distanceFilterMeters'] as num?)?.toInt() ?? 25)
              .clamp(10, 200)
              .toInt(),
      batchSize: ((json?['batchSize'] as num?)?.toInt() ?? 25)
          .clamp(10, 500)
          .toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'activeIntervalSeconds': intervalSeconds,
    'distanceFilterMeters': distanceFilterMeters,
    'batchSize': batchSize,
  };
}

class TrackingSession {
  const TrackingSession({
    required this.localId,
    required this.id,
    required this.serviceId,
    required this.status,
    required this.policy,
    this.lastSequence = 0,
  });

  final String localId;
  final String? id;
  final String serviceId;
  final String status;
  final TrackingPolicy policy;
  final int lastSequence;

  bool get isActive => status == 'ACTIVE' || status == 'PROVISIONAL';

  factory TrackingSession.fromJson(
    Map<String, dynamic> json, {
    required String serviceId,
    String? localId,
    TrackingPolicy? fallbackPolicy,
  }) {
    final id = json['id'] as String?;
    return TrackingSession(
      localId: localId ?? (json['clientSessionId'] as String?) ?? id ?? '',
      id: id,
      serviceId: serviceId,
      status: json['status'] as String? ?? 'ACTIVE',
      policy: fallbackPolicy ?? const TrackingPolicy(),
      lastSequence: (json['lastSequence'] as num?)?.toInt() ?? 0,
    );
  }
}
