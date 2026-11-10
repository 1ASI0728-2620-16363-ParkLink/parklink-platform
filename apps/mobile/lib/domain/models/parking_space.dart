class ParkingSpace {
  const ParkingSpace({
    required this.id,
    required this.revision,
    required this.title,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.hourlyRate,
    required this.description,
    required this.features,
    this.photoUrl,
    this.distanceMeters,
  });
  final String id, title, address, description;
  final int revision, hourlyRate;
  final double latitude, longitude;
  final List<String> features;
  final String? photoUrl;
  final double? distanceMeters;
  factory ParkingSpace.fromJson(Map<String, dynamic> json) {
    final body = json['body'] as Map<String, dynamic>;
    final photo = Uri.tryParse(body['photoUrl'] as String? ?? '');
    return ParkingSpace(
      id: json['id'] as String,
      revision: json['revision'] as int,
      title: body['title'] as String,
      address: body['address'] as String,
      latitude: (body['latitude'] as num).toDouble(),
      longitude: (body['longitude'] as num).toDouble(),
      hourlyRate: body['hourlyRate'] as int,
      description: body['description'] as String,
      features: List<String>.from(body['features'] as List),
      photoUrl: photo?.scheme == 'https' && photo!.host.isNotEmpty
          ? photo.toString()
          : null,
      distanceMeters: num.tryParse('${json['distance_m']}')?.toDouble(),
    );
  }
}
