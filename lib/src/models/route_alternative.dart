// ignore_for_file: public_member_api_docs

import 'package:flutter_mapbox_navigation_plus/src/helpers.dart';
import 'package:flutter_mapbox_navigation_plus/src/models/map_shapes.dart';

/// Lightweight summary of a single route returned by a `buildRoute`/
/// `startNavigation` request. Delivered through the `alternative_routes` event
/// so a Flutter UI can show the available options (ETA / distance) and let the
/// user pick one with `selectAlternativeRoute`.
class RouteAlternative {
  RouteAlternative({
    required this.index,
    required this.distance,
    required this.duration,
    this.isPrimary = false,
  });

  RouteAlternative.fromJson(Map<String, dynamic> json)
      : index = json['index'] as int? ?? 0,
        distance = isNullOrZero(json['distance'] as num?)
            ? 0.0
            : (json['distance'] as num).toDouble(),
        duration = isNullOrZero(json['duration'] as num?)
            ? 0.0
            : (json['duration'] as num).toDouble(),
        isPrimary = json['isPrimary'] as bool? ?? false,
        geometry = _parseGeometry(json['geometry']);

  static List<LatLng> _parseGeometry(dynamic raw) {
    if (raw is! List) return const <LatLng>[];
    final points = <LatLng>[];
    for (final p in raw) {
      if (p is List && p.length >= 2) {
        final lat = (p[0] as num?)?.toDouble();
        final lng = (p[1] as num?)?.toDouble();
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  /// Position of this route in the result list. Pass it to
  /// `selectAlternativeRoute` to promote it to the primary route.
  final int index;

  /// Total distance of the route in meters.
  final double distance;

  /// Estimated travel time of the route in seconds.
  final double duration;

  /// Whether this is currently the primary (selected) route.
  final bool isPrimary;

  /// Decoded route geometry as a list of coordinates — handy for drawing a
  /// preview/minimap of the route. May be empty if not provided by the platform.
  final List<LatLng> geometry;

  static List<RouteAlternative> listFromJson(dynamic data) {
    if (data is! List) return <RouteAlternative>[];
    return data
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => RouteAlternative.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
