// ignore_for_file: public_member_api_docs

import 'package:flutter_mapbox_navigation_plus/src/models/way_point.dart';

/// A place returned by forward/reverse geocoding or by retrieving a search
/// suggestion.
class GeocodingFeature {
  GeocodingFeature({
    required this.id,
    required this.name,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
    this.featureType,
  });

  /// Parses a single GeoJSON feature from the Mapbox Geocoding v6 / Search Box
  /// `retrieve` response.
  static GeocodingFeature? fromFeatureJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List?;
    if (coords == null || coords.length < 2) return null;
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    final props = (json['properties'] as Map<String, dynamic>?) ?? const {};
    return GeocodingFeature(
      id: (props['mapbox_id'] ?? json['id'] ?? '').toString(),
      name: (props['name'] ?? props['name_preferred'] ?? '').toString(),
      fullAddress:
          (props['full_address'] ?? props['place_formatted'] ?? props['name'] ?? '')
              .toString(),
      latitude: lat,
      longitude: lng,
      featureType: props['feature_type'] as String?,
    );
  }

  /// Stable Mapbox id of the place.
  final String id;

  /// Short display name (e.g. "Starbucks").
  final String name;

  /// Full formatted address.
  final String fullAddress;

  /// Latitude in degrees.
  final double latitude;

  /// Longitude in degrees.
  final double longitude;

  /// Mapbox feature type (e.g. `address`, `poi`, `place`).
  final String? featureType;

  /// Convenience: turn this place into a navigation [WayPoint].
  WayPoint toWayPoint() => WayPoint(
        name: name.isNotEmpty ? name : fullAddress,
        latitude: latitude,
        longitude: longitude,
      );
}
