import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_driver/data/repositories/parking_repository.dart';
import 'package:mobile_driver/data/services/parking_location_service.dart';
import 'package:mobile_driver/domain/models/location_point.dart';
import 'package:mobile_driver/domain/models/parking_space.dart';
import 'package:mobile_driver/ui/features/parking/view_models/nearby_search_view_model.dart';
import 'package:mobile_driver/ui/features/parking/view_models/parking_view_model.dart';

const devicePoint = LocationPoint(
  latitude: -12.12,
  longitude: -77.03,
  accuracy: 12,
);
const mapPoint = LocationPoint(
  latitude: -12.04,
  longitude: -77.04,
  accuracy: 0,
);

Map<String, dynamic> spaceJson(String id, {String? photo}) => {
  'id': id,
  'revision': 3,
  'distance_m': '120.5',
  'body': {
    'title': 'Registered space $id',
    'address': 'Registered address $id',
    'latitude': -12.12,
    'longitude': -77.03,
    'hourlyRate': 750,
    'description': '',
    'features': <String>[],
    'photoUrl': ?photo,
  },
};

class FakeLocation extends ParkingLocationService {
  ParkingLocationIssue? issue;
  bool? permissionRequested;
  @override
  Future<LocationPoint> current({bool requestPermission = false}) async {
    permissionRequested = requestPermission;
    if (issue != null) throw ParkingLocationException(issue!);
    return devicePoint;
  }
}

void main() {
  test('real API fields retain distance and only HTTPS publication photos', () {
    final space = ParkingSpace.fromJson(
      spaceJson('one', photo: 'https://photos.example.org/one.jpg'),
    );
    expect(space.photoUrl, 'https://photos.example.org/one.jpg');
    expect(space.distanceMeters, 120.5);
    expect(ParkingSpace.fromJson(spaceJson('two')).photoUrl, isNull);
    expect(
      ParkingSpace.fromJson(
        spaceJson('two', photo: 'http://photos.example.org/two.jpg'),
      ).photoUrl,
      isNull,
    );
  });
  test(
    'nearby search uses GPS, requests interval availability and skips occupied candidates',
    () async {
      final checked = <String>[];
      final repo = ParkingRepository(
        client: MockClient((request) async {
          final q = request.url.queryParameters;
          if (request.url.path == '/discovery/search') {
            expect(q['latitude'], '${devicePoint.latitude}');
            expect(q['longitude'], '${devicePoint.longitude}');
            expect(q['sort'], 'nearest');
            expect(q['radius'], '5000');
            expect(
              DateTime.parse(q['end']!).difference(DateTime.parse(q['start']!)),
              const Duration(hours: 1),
            );
            return http.Response(
              jsonEncode({
                'items': [spaceJson('occupied'), spaceJson('free')],
              }),
              200,
            );
          }
          expect(request.url.path, '/reservations/availability');
          checked.add(q['spaceId']!);
          return http.Response(
            jsonEncode({'available': q['spaceId'] == 'free'}),
            200,
          );
        }),
      );
      final location = FakeLocation();
      final vm = NearbySearchViewModel(
        repo,
        mapCenter: mapPoint,
        locationService: location,
      );
      await vm.search(requestPermission: true);
      expect(vm.state, NearbySearchState.found);
      expect(vm.result!.space.id, 'free');
      expect(vm.origin, devicePoint);
      expect(vm.result!.fromDevice, isTrue);
      expect(location.permissionRequested, isTrue);
      expect(checked, ['occupied', 'free']);
      vm.dispose();
      repo.dispose();
    },
  );
  test(
    'permission denial never silently searches from a fabricated user position',
    () async {
      var requests = 0;
      final repo = ParkingRepository(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      final location = FakeLocation()..issue = ParkingLocationIssue.blocked;
      final vm = NearbySearchViewModel(
        repo,
        mapCenter: mapPoint,
        locationService: location,
      );
      await vm.search();
      expect(vm.state, NearbySearchState.locationRequired);
      expect(vm.locationIssue, ParkingLocationIssue.blocked);
      expect(vm.result, isNull);
      expect(requests, 0);
      vm.dispose();
      repo.dispose();
    },
  );
  test(
    'explicit map alternative queries map coordinates and preserves empty state',
    () async {
      final location = FakeLocation()..issue = ParkingLocationIssue.disabled;
      final repo = ParkingRepository(
        client: MockClient((request) async {
          expect(
            request.url.queryParameters['latitude'],
            '${mapPoint.latitude}',
          );
          return http.Response(jsonEncode({'items': []}), 200);
        }),
      );
      final vm = NearbySearchViewModel(
        repo,
        mapCenter: mapPoint,
        locationService: location,
      );
      await vm.search(useMapCenter: true);
      expect(vm.state, NearbySearchState.empty);
      expect(vm.result, isNull);
      expect(vm.fromDevice, isFalse);
      expect(location.permissionRequested, isNull);
      vm.dispose();
      repo.dispose();
    },
  );
  test('connection errors have no invented fallback inventory', () async {
    final repo = ParkingRepository(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    final vm = NearbySearchViewModel(
      repo,
      mapCenter: mapPoint,
      locationService: FakeLocation(),
    );
    await vm.search();
    expect(vm.state, NearbySearchState.error);
    expect(vm.result, isNull);
    vm.dispose();
    repo.dispose();
  });
  test('map search ignores a stale response after the camera moved', () async {
    final first = Completer<http.Response>();
    var requests = 0;
    final repo = ParkingRepository(
      client: MockClient((_) async {
        requests++;
        if (requests == 1) return first.future;
        return http.Response(
          jsonEncode({
            'items': [spaceJson('current')],
          }),
          200,
        );
      }),
    );
    final vm = ParkingViewModel(repo);
    final oldRequest = vm.search();
    await Future<void>.delayed(Duration.zero);
    vm.latitude = devicePoint.latitude;
    await vm.search();
    first.complete(
      http.Response(
        jsonEncode({
          'items': [spaceJson('stale')],
        }),
        200,
      ),
    );
    await oldRequest;
    expect(vm.spaces.single.id, 'current');
    expect(vm.mapBusy, isFalse);
    vm.dispose();
    repo.dispose();
  });
}
