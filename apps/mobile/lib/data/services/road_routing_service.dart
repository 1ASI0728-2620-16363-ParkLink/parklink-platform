import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoadRoutingException implements Exception {
  const RoadRoutingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AddressSuggestion {
  const AddressSuggestion({required this.label, this.placeId, this.point});

  final String label;
  final String? placeId;
  final LatLng? point;
}

class RoadRoutingService {
  const RoadRoutingService();

  /// Set GOOGLE_MAPS_API_KEY via --dart-define when Google services are used.
  static const _googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static const _headers = {
    'accept': 'application/json',
    'user-agent': 'RutasApp/1.0 (com.rutasapp.mobile_driver)',
  };

  Future<List<AddressSuggestion>> addressSuggestions(String query) async {
    if (query.trim().length < 3) return const [];
    final uri = Uri.https('places.googleapis.com', '/v1/places:autocomplete', {
      'fields':
          'suggestions.placePrediction.placeId,'
          'suggestions.placePrediction.text.text',
    });
    final response = await http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            'x-goog-api-key': _apiKey,
          },
          body: jsonEncode({
            'input': query.trim(),
            'languageCode': 'es',
            'regionCode': 'PE',
            'includedRegionCodes': ['pe'],
            'locationBias': {
              'circle': {
                'center': {'latitude': -12.0464, 'longitude': -77.0428},
                'radius': 50000.0,
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const RoadRoutingException(
        'Google Maps no pudo buscar direcciones en este momento.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawSuggestions = body['suggestions'] as List<dynamic>? ?? const [];
    final suggestions = <AddressSuggestion>[];
    for (final rawSuggestion in rawSuggestions) {
      if (rawSuggestion is! Map<String, dynamic>) continue;
      final prediction = rawSuggestion['placePrediction'];
      if (prediction is! Map<String, dynamic>) continue;
      final text = prediction['text'];
      final label = text is Map<String, dynamic>
          ? text['text'] as String?
          : null;
      final placeId = prediction['placeId'] as String?;
      if (label == null || label.trim().isEmpty || placeId == null) continue;
      suggestions.add(AddressSuggestion(label: label.trim(), placeId: placeId));
    }
    return suggestions.take(5).toList(growable: false);
  }

  Future<AddressSuggestion> resolveSuggestion(
    AddressSuggestion suggestion,
  ) async {
    if (suggestion.point != null) return suggestion;
    final placeId = suggestion.placeId;
    if (placeId == null) {
      return AddressSuggestion(
        label: suggestion.label,
        point: await geocode(suggestion.label),
      );
    }

    // La máscara de campos viaja como query param `fields`, NO como header
    // `X-Goog-FieldMask`: Dart normaliza los headers a minúscula y este
    // endpoint rechaza `x-goog-field-mask` en minúscula con
    // 400 INVALID_ARGUMENT ("FieldMask is a required parameter"). Ese 400 era
    // lo que rompía el tap sobre cualquier sugerencia.
    final uri = Uri.https(
      'places.googleapis.com',
      '/v1/places/${Uri.encodeComponent(placeId)}',
      {
        'languageCode': 'es',
        'regionCode': 'PE',
        'fields': 'formattedAddress,location',
      },
    );
    final response = await http
        .get(
          uri,
          headers: {'accept': 'application/json', 'x-goog-api-key': _apiKey},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final location = body['location'];
      if (location is Map<String, dynamic>) {
        return AddressSuggestion(
          label: body['formattedAddress'] as String? ?? suggestion.label,
          placeId: placeId,
          point: LatLng(
            (location['latitude'] as num).toDouble(),
            (location['longitude'] as num).toDouble(),
          ),
        );
      }
    }

    // Si Place Details no devuelve coordenadas, se geocodifica la etiqueta en
    // vez de dejar al usuario sin poder confirmar la dirección.
    return AddressSuggestion(
      label: suggestion.label,
      placeId: placeId,
      point: await geocode(suggestion.label),
    );
  }

  Future<LatLng> geocode(String address) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': address,
      'key': _apiKey,
      'language': 'es',
      'region': 'pe',
      'components': 'country:PE',
    });
    final response = await http
        .get(uri, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const RoadRoutingException(
        'No se pudo buscar la dirección. Intenta nuevamente.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>? ?? const [];
    if (results.isEmpty) {
      throw RoadRoutingException(
        'No encontramos “$address”. Agrega distrito, ciudad y país.',
      );
    }

    final place = results.first as Map<String, dynamic>;
    final geometry = place['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;
    return LatLng(
      (location['lat'] as num).toDouble(),
      (location['lng'] as num).toDouble(),
    );
  }

  Future<String> reverseGeocode(LatLng point) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '${point.latitude},${point.longitude}',
      'key': _apiKey,
      'language': 'es',
      'region': 'pe',
    });
    final response = await http
        .get(uri, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const RoadRoutingException(
        'No se pudo obtener la dirección de tu ubicación.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>? ?? const [];
    if (results.isEmpty) {
      throw const RoadRoutingException(
        'Google Maps no encontró una dirección para tu ubicación.',
      );
    }
    return (results.first as Map<String, dynamic>)['formatted_address']
        as String;
  }

  String get _apiKey {
    if (_googleMapsApiKey.trim().isEmpty) {
      throw const RoadRoutingException(
        'Google Maps no está configurado en esta compilación.',
      );
    }
    return _googleMapsApiKey;
  }

  /// Cuánto falta para llegar, con el tráfico del momento.
  ///
  /// Devuelve `null` en vez de una estimación inventada cuando Google no
  /// responde o no hay ruta transitable: un tiempo equivocado es peor que
  /// ninguno para quien está esperando en la puerta.
  ///
  /// Va por Routes API y no por OSRM —que es lo que usa [route]— porque el
  /// router público no conoce el tráfico, y en Lima esa diferencia es la mitad
  /// del viaje. Se pide sólo `duration` para no pagar por la geometría.
  Future<Duration?> tiempoHastaDestino(LatLng desde, LatLng hasta) async {
    final uri = Uri.https('routes.googleapis.com', '/directions/v2:computeRoutes');
    try {
      final response = await http
          .post(
            uri,
            headers: {
              ..._headers,
              'content-type': 'application/json',
              'x-goog-api-key': _apiKey,
              'x-goog-fieldmask': 'routes.duration',
            },
            body: jsonEncode({
              'origin': {
                'location': {
                  'latLng': {
                    'latitude': desde.latitude,
                    'longitude': desde.longitude,
                  },
                },
              },
              'destination': {
                'location': {
                  'latLng': {
                    'latitude': hasta.latitude,
                    'longitude': hasta.longitude,
                  },
                },
              },
              'travelMode': 'DRIVE',
              'routingPreference': 'TRAFFIC_AWARE',
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return null;
      // Routes API devuelve la duración como texto en segundos: "930s".
      final crudo = (routes.first as Map<String, dynamic>)['duration'] as String?;
      if (crudo == null || !crudo.endsWith('s')) return null;
      final segundos = int.tryParse(crudo.substring(0, crudo.length - 1));
      if (segundos == null) return null;
      return Duration(seconds: segundos);
    } catch (_) {
      return null;
    }
  }

  Future<List<LatLng>> route(LatLng start, LatLng end) async {
    final coordinates =
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}';
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/$coordinates',
      {'overview': 'full', 'geometries': 'geojson'},
    );
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw const RoadRoutingException('No se pudo calcular la ruta vial.');
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = body['routes'] as List<dynamic>? ?? const [];
        if (body['code'] != 'Ok' || routes.isEmpty) {
          throw const RoadRoutingException(
            'No encontramos una ruta transitable entre ambos puntos.',
          );
        }

        final firstRoute = routes.first as Map<String, dynamic>;
        final geometry = firstRoute['geometry'] as Map<String, dynamic>;
        final points = geometry['coordinates'] as List<dynamic>;
        return points
            .map((point) {
              final coordinate = point as List<dynamic>;
              return LatLng(
                (coordinate[1] as num).toDouble(),
                (coordinate[0] as num).toDouble(),
              );
            })
            .toList(growable: false);
      } catch (_) {
        if (attempt == 3) {
          throw const RoadRoutingException('No se pudo calcular la ruta vial.');
        }
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
    throw const RoadRoutingException('No se pudo calcular la ruta vial.');
  }
}
