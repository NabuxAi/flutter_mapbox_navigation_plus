// ignore_for_file: public_member_api_docs

import 'package:flutter_mapbox_navigation_plus/src/helpers.dart';

/// A camera position on the map, returned by `getCameraPosition` and used to
/// describe a target for `moveCamera`.
class CameraPosition {
  CameraPosition({
    required this.latitude,
    required this.longitude,
    this.zoom,
    this.bearing,
    this.tilt,
  });

  CameraPosition.fromMap(Map<dynamic, dynamic> map)
      : latitude = (map['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude = (map['longitude'] as num?)?.toDouble() ?? 0.0,
        zoom = isNullOrZero(map['zoom'] as num?)
            ? null
            : (map['zoom'] as num).toDouble(),
        bearing = (map['bearing'] as num?)?.toDouble(),
        tilt = (map['tilt'] as num?)?.toDouble();

  /// Latitude of the camera target in degrees.
  final double latitude;

  /// Longitude of the camera target in degrees.
  final double longitude;

  /// Zoom level (0–22), or null if unspecified.
  final double? zoom;

  /// Camera bearing in degrees (0 = north), or null if unspecified.
  final double? bearing;

  /// Camera tilt/pitch in degrees (0 = top-down), or null if unspecified.
  final double? tilt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'zoom': zoom,
        'bearing': bearing,
        'tilt': tilt,
      };
}
