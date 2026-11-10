class InAppNotification {
  const InAppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.serviceId,
    this.requestId,
    this.type,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String title;
  final String message;
  final String? serviceId;
  final String? requestId;
  final String? type;
  final DateTime? createdAt;
  final bool read;

  factory InAppNotification.fromJson(Map<String, dynamic> json) {
    final data = _notificationMap(json['payload'] ?? json['data']);
    final metadata =
        _notificationMap(json['metadata']) ??
        _notificationMap(data?['metadata']);
    final request =
        _notificationMap(json['request']) ??
        _notificationMap(data?['request']) ??
        _notificationMap(metadata?['request']);
    return InAppNotification(
      id:
          _notificationString(json['id'] ?? json['notificationId']) ??
          '${json['createdAt'] ?? json['created_at'] ?? ''}:'
              '${json['title'] ?? json['subject'] ?? 'notification'}',
      title: (json['title'] ?? json['subject'] ?? 'Nueva asignación')
          .toString(),
      message: (json['message'] ?? json['body'] ?? 'Tienes una actualización.')
          .toString(),
      serviceId: _notificationString(
        json['serviceId'] ??
            json['service_id'] ??
            data?['serviceId'] ??
            data?['service_id'] ??
            metadata?['serviceId'] ??
            metadata?['service_id'],
      ),
      requestId: _notificationString(
        json['requestId'] ??
            json['request_id'] ??
            json['serviceRequestId'] ??
            data?['requestId'] ??
            data?['request_id'] ??
            data?['serviceRequestId'] ??
            metadata?['requestId'] ??
            metadata?['request_id'] ??
            metadata?['serviceRequestId'] ??
            request?['id'],
      ),
      type: _notificationString(
        json['type'] ??
            json['eventType'] ??
            data?['type'] ??
            data?['eventType'] ??
            metadata?['type'],
      ),
      createdAt: _date(json['createdAt'] ?? json['created_at']),
      read:
          _notificationBool(json['read'] ?? json['isRead']) ??
          (json['readAt'] != null || json['read_at'] != null),
    );
  }

  InAppNotification copyWith({bool? read}) => InAppNotification(
    id: id,
    title: title,
    message: message,
    serviceId: serviceId,
    requestId: requestId,
    type: type,
    createdAt: createdAt,
    read: read ?? this.read,
  );

  String? get targetServiceId => serviceId ?? requestId;

  bool get isServiceRequest {
    final normalized = (type ?? '').toUpperCase();
    return targetServiceId != null &&
        (normalized.isEmpty ||
            normalized.contains('SERVICE_REQUEST') ||
            normalized.contains('REQUEST') ||
            normalized.contains('SOLICITUD') ||
            (normalized.contains('SERVICE') &&
                (normalized.contains('NEW') ||
                    normalized.contains('CREATED'))));
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

Map<String, dynamic>? _notificationMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

String? _notificationString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

bool? _notificationBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
  }
  return null;
}
