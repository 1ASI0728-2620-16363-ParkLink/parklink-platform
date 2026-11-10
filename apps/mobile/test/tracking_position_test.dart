import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/domain/models/location_point.dart';
import 'package:mobile_driver/domain/models/tracking_position.dart';
import 'package:mobile_driver/domain/models/tracking_session.dart';

void main() {
  test('omits unavailable or invalid optional GPS measurements', () {
    const position = TrackingPosition(
      clientPositionId: '00000000-0000-4000-8000-000000000001',
      sequence: 1,
      location: LocationPoint(
        latitude: -12.0464,
        longitude: -77.0428,
        accuracy: 12000,
        speed: -1,
        heading: -1,
        altitude: 25000,
        provider: '',
      ),
    );

    final json = position.toJson();

    expect(json['accuracyM'], 10000);
    expect(json, isNot(contains('speedMps')));
    expect(json, isNot(contains('headingDeg')));
    expect(json, isNot(contains('altitudeM')));
    expect(json, isNot(contains('provider')));
  });

  test('keeps valid optional GPS measurements', () {
    const position = TrackingPosition(
      clientPositionId: '00000000-0000-4000-8000-000000000002',
      sequence: 2,
      location: LocationPoint(
        latitude: -12.0464,
        longitude: -77.0428,
        accuracy: 8,
        speed: 12,
        heading: 180,
        altitude: 120,
        provider: 'core_location',
      ),
    );

    expect(position.toJson(), containsPair('speedMps', 12));
    expect(position.toJson(), containsPair('headingDeg', 180));
    expect(position.toJson(), containsPair('altitudeM', 120));
    expect(position.toJson(), containsPair('provider', 'core_location'));
  });

  test('restores the last server sequence for continued tracking', () {
    final session = TrackingSession.fromJson(const {
      'id': '00000000-0000-4000-8000-000000000003',
      'status': 'ACTIVE',
      'lastSequence': 9,
    }, serviceId: '00000000-0000-4000-8000-000000000004');

    expect(session.lastSequence, 9);
  });
}
