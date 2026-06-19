import 'dart:convert';

import 'package:flutter_mapbox_navigation_plus/src/models/map_shapes.dart';
import 'package:flutter_mapbox_navigation_plus/src/search/geocoding_feature.dart';
import 'package:flutter_mapbox_navigation_plus/src/search/search_suggestion.dart';
import 'package:http/http.dart' as http;

/// A lightweight, pure-Dart client for Mapbox place search and geocoding.
///
/// It calls the public Mapbox REST APIs directly (no native SDK), so it works
/// identically on Android, iOS and web:
///
/// * [forwardGeocode] / [reverseGeocode] use the **Geocoding v6** API.
/// * [suggest] + [retrieve] use the **Search Box** API for interactive
///   autocomplete (cheaper, session-billed). Generate one [sessionToken] per
///   search session and reuse it across [suggest] calls and the final
///   [retrieve].
///
/// Requires a Mapbox **public** access token (`pk.…`).
class MapBoxSearch {
  MapBoxSearch({
    required this.accessToken,
    this.language = 'en',
    this.country,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Mapbox public access token (`pk.…`).
  final String accessToken;

  /// IETF language tag for results (e.g. `en`, `fa`).
  final String language;

  /// Optional ISO 3166-1 country code filter (e.g. `om`, `us`).
  final String? country;

  final http.Client _client;

  static const _geocodeHost = 'api.mapbox.com';

  /// Forward geocoding: turn a free-form [query] into a ranked list of places.
  /// Pass [proximity] to bias results toward a location.
  Future<List<GeocodingFeature>> forwardGeocode(
    String query, {
    LatLng? proximity,
    int limit = 5,
  }) async {
    final params = <String, String>{
      'q': query,
      'access_token': accessToken,
      'language': language,
      'limit': '$limit',
      if (proximity != null)
        'proximity': '${proximity.longitude},${proximity.latitude}',
      if (country != null) 'country': country!,
    };
    final uri = Uri.https(_geocodeHost, '/search/geocode/v6/forward', params);
    final json = await _getJson(uri);
    return _parseFeatures(json);
  }

  /// Reverse geocoding: turn a coordinate into the place(s) at that point.
  Future<List<GeocodingFeature>> reverseGeocode(
    double latitude,
    double longitude, {
    int limit = 1,
  }) async {
    final params = <String, String>{
      'longitude': '$longitude',
      'latitude': '$latitude',
      'access_token': accessToken,
      'language': language,
      'limit': '$limit',
    };
    final uri = Uri.https(_geocodeHost, '/search/geocode/v6/reverse', params);
    final json = await _getJson(uri);
    return _parseFeatures(json);
  }

  /// Interactive autocomplete. Returns suggestions without coordinates; call
  /// [retrieve] with the chosen suggestion's `mapboxId` and the same
  /// [sessionToken] to get its location.
  Future<List<SearchSuggestion>> suggest(
    String query, {
    required String sessionToken,
    LatLng? proximity,
    int limit = 5,
  }) async {
    final params = <String, String>{
      'q': query,
      'access_token': accessToken,
      'session_token': sessionToken,
      'language': language,
      'limit': '$limit',
      if (proximity != null)
        'proximity': '${proximity.longitude},${proximity.latitude}',
      if (country != null) 'country': country!,
    };
    final uri = Uri.https(_geocodeHost, '/search/searchbox/v1/suggest', params);
    final json = await _getJson(uri);
    final suggestions = json['suggestions'];
    if (suggestions is! List) return <SearchSuggestion>[];
    return suggestions
        .whereType<Map<String, dynamic>>()
        .map(SearchSuggestion.fromJson)
        .whereType<SearchSuggestion>()
        .toList();
  }

  /// Resolves a suggestion (by its `mapboxId`) into a full [GeocodingFeature]
  /// with coordinates. Reuse the [sessionToken] from the [suggest] call.
  Future<GeocodingFeature?> retrieve(
    String mapboxId, {
    required String sessionToken,
  }) async {
    final params = <String, String>{
      'access_token': accessToken,
      'session_token': sessionToken,
    };
    final uri = Uri.https(
      _geocodeHost,
      '/search/searchbox/v1/retrieve/$mapboxId',
      params,
    );
    final json = await _getJson(uri);
    final features = json['features'];
    if (features is! List || features.isEmpty) return null;
    return GeocodingFeature.fromFeatureJson(
      features.first as Map<String, dynamic>,
    );
  }

  /// Releases the underlying HTTP client. Call when done if you passed no
  /// external [http.Client].
  void dispose() => _client.close();

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw MapBoxSearchException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  List<GeocodingFeature> _parseFeatures(Map<String, dynamic> json) {
    final features = json['features'];
    if (features is! List) return <GeocodingFeature>[];
    return features
        .whereType<Map<String, dynamic>>()
        .map(GeocodingFeature.fromFeatureJson)
        .whereType<GeocodingFeature>()
        .toList();
  }
}

/// Thrown when a Mapbox search/geocoding request returns a non-200 response.
class MapBoxSearchException implements Exception {
  MapBoxSearchException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'MapBoxSearchException($statusCode): $body';
}
