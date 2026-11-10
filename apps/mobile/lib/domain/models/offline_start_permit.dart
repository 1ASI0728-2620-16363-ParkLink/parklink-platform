class OfflineStartPermit {
  const OfflineStartPermit({
    required this.token,
    required this.notBefore,
    required this.expiresAt,
  });

  final String token;
  final DateTime? notBefore;
  final DateTime expiresAt;

  bool get isValid {
    final now = DateTime.now().toUtc();
    return (notBefore == null || !now.isBefore(notBefore!)) &&
        now.isBefore(expiresAt);
  }

  factory OfflineStartPermit.fromJson(Object? value) {
    if (value is String) {
      return OfflineStartPermit(
        token: value,
        notBefore: null,
        // An opaque legacy token without an explicit window is never trusted
        // for offline start. Online start can still send it to the server.
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    final json = value! as Map<String, dynamic>;
    return OfflineStartPermit(
      token: (json['token'] ?? json['permit']) as String,
      notBefore: _parseDate(json['notBefore'] ?? json['not_before']),
      expiresAt:
          _parseDate(json['expiresAt'] ?? json['expires_at']) ??
          DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'notBefore': notBefore?.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
}

DateTime? _parseDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}
