class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.driverId,
  });

  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? driverId;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String,
      role: json['role'] as String,
      driverId: json['driverId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'role': role,
      'driverId': driverId,
    };
  }
}

class DriverProfileDetails {
  const DriverProfileDetails({
    required this.fullName,
    required this.documentNumber,
    required this.status,
    required this.phone,
    required this.avatarUrl,
    required this.vehiclePlate,
    required this.vehicleModel,
    required this.vehicleType,
    required this.seatCount,
    required this.dedicatedTo,
    required this.receivesTripOffers,
  });

  final String fullName;
  final String documentNumber;
  final String status;
  final String? phone;
  final String? avatarUrl;
  final String? vehiclePlate;
  final String? vehicleModel;
  final String? vehicleType;
  final int? seatCount;
  final String? dedicatedTo;
  final bool receivesTripOffers;

  bool get isDedicated => dedicatedTo?.trim().isNotEmpty ?? false;

  factory DriverProfileDetails.fromJson(Map<String, dynamic> json) {
    final vehicle = json['vehicle'] as Map<String, dynamic>?;
    return DriverProfileDetails(
      fullName: json['fullName'] as String? ?? 'Conductor',
      documentNumber: json['documentNumber'] as String? ?? 'No registrado',
      status: json['status'] as String? ?? 'UNKNOWN',
      phone: json['phone'] as String?,
      avatarUrl: json['avatar'] as String?,
      vehiclePlate: vehicle?['plate'] as String?,
      vehicleModel: vehicle?['model'] as String?,
      vehicleType: vehicle?['vehicleType'] as String?,
      seatCount: (vehicle?['seatCount'] as num?)?.toInt(),
      dedicatedTo: _optionalString(json['dedicatedTo']),
      receivesTripOffers: json['receivesTripOffers'] as bool? ?? true,
    );
  }
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.absoluteExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime absoluteExpiresAt;
  final UserProfile user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final tokens = json['tokens'] as Map<String, dynamic>;
    final now = DateTime.now().toUtc();
    final expiresIn = (tokens['expiresIn'] as num?)?.toInt() ?? 900;
    final refreshExpiresIn =
        (tokens['refreshExpiresIn'] as num?)?.toInt() ??
        const Duration(days: 30).inSeconds;
    return AuthSession(
      accessToken: tokens['accessToken'] as String,
      refreshToken: tokens['refreshToken'] as String,
      accessExpiresAt: now.add(Duration(seconds: expiresIn)),
      absoluteExpiresAt: now.add(Duration(seconds: refreshExpiresIn)),
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
