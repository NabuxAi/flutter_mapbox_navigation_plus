import 'dart:convert';

import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('MapBoxSearch', () {
    test('forwardGeocode parses features into GeocodingFeature', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/search/geocode/v6/forward');
        expect(request.url.queryParameters['q'], 'coffee');
        expect(request.url.queryParameters['access_token'], 'pk.test');
        return http.Response(
          jsonEncode({
            'features': [
              {
                'id': 'feat1',
                'geometry': {
                  'type': 'Point',
                  'coordinates': [58.3829, 23.5880],
                },
                'properties': {
                  'mapbox_id': 'mb1',
                  'name': 'Coffee Shop',
                  'full_address': 'Coffee Shop, Muscat',
                  'feature_type': 'poi',
                },
              },
            ],
          }),
          200,
        );
      });
      final search = MapBoxSearch(accessToken: 'pk.test', client: client);

      final results = await search.forwardGeocode('coffee');

      expect(results, hasLength(1));
      expect(results.first.name, 'Coffee Shop');
      expect(results.first.latitude, 23.5880);
      expect(results.first.longitude, 58.3829);
      expect(results.first.featureType, 'poi');
      expect(results.first.toWayPoint().latitude, 23.5880);
    });

    test('suggest then retrieve resolves coordinates', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/search/searchbox/v1/suggest') {
          expect(request.url.queryParameters['session_token'], 'sess');
          return http.Response(
            jsonEncode({
              'suggestions': [
                {
                  'mapbox_id': 'abc',
                  'name': 'Airport',
                  'full_address': 'Muscat Intl Airport',
                  'distance': 1234.5,
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.path, '/search/searchbox/v1/retrieve/abc');
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'coordinates': [58.2844, 23.5933],
                },
                'properties': {
                  'mapbox_id': 'abc',
                  'name': 'Airport',
                  'full_address': 'Muscat Intl Airport',
                },
              },
            ],
          }),
          200,
        );
      });
      final search = MapBoxSearch(accessToken: 'pk.test', client: client);

      final suggestions = await search.suggest('air', sessionToken: 'sess');
      expect(suggestions, hasLength(1));
      expect(suggestions.first.mapboxId, 'abc');
      expect(suggestions.first.distanceMeters, 1234.5);

      final place = await search.retrieve('abc', sessionToken: 'sess');
      expect(place, isNotNull);
      expect(place!.latitude, 23.5933);
      expect(place.longitude, 58.2844);
    });

    test('non-200 throws MapBoxSearchException', () async {
      final client = MockClient((request) async => http.Response('nope', 401));
      final search = MapBoxSearch(accessToken: 'bad', client: client);
      expect(
        () => search.forwardGeocode('x'),
        throwsA(isA<MapBoxSearchException>()),
      );
    });
  });
}
