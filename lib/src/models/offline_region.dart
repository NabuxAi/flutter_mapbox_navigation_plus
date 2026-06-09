/// Describes an offline region to download (map tiles + routing tiles).
///
/// The region is an arbitrary polygon supplied as its outer ring. Both the map
/// and the navigation/routing tiles for the area are downloaded so navigation
/// works fully offline.
class OfflineRegion {
  /// Creates an offline region from an explicit polygon ring.
  ///
  /// [coordinates] is the outer ring as a list of `[longitude, latitude]`
  /// pairs. The ring should have at least 3 points; it is closed automatically.
  OfflineRegion({
    required this.id,
    required this.coordinates,
    this.minZoom = 0,
    this.maxZoom = 16,
    this.styleUrl,
  });

  /// Convenience constructor building a rectangular region from a bounding box.
  factory OfflineRegion.fromBounds({
    required String id,
    required double southWestLat,
    required double southWestLng,
    required double northEastLat,
    required double northEastLng,
    int minZoom = 0,
    int maxZoom = 16,
    String? styleUrl,
  }) {
    return OfflineRegion(
      id: id,
      coordinates: <List<double>>[
        <double>[southWestLng, southWestLat],
        <double>[northEastLng, southWestLat],
        <double>[northEastLng, northEastLat],
        <double>[southWestLng, northEastLat],
        <double>[southWestLng, southWestLat],
      ],
      minZoom: minZoom,
      maxZoom: maxZoom,
      styleUrl: styleUrl,
    );
  }

  /// Unique identifier for the region (used to update or remove it later).
  final String id;

  /// Outer ring of the polygon as `[longitude, latitude]` pairs.
  final List<List<double>> coordinates;

  /// Minimum zoom level to download.
  final int minZoom;

  /// Maximum zoom level to download. Higher values mean much larger downloads.
  final int maxZoom;

  /// Optional map style URL to download tiles for. Defaults to the platform's
  /// standard style when null.
  final String? styleUrl;

  /// Serializes the region for the platform channel.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'coordinates': coordinates,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'styleUrl': styleUrl,
    };
  }
}
