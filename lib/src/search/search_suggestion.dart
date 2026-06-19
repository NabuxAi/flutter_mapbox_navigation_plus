// ignore_for_file: public_member_api_docs

/// An autocomplete suggestion from the Mapbox Search Box `suggest` endpoint.
///
/// A suggestion has no coordinates yet — call `MapBoxSearch.retrieve` with its
/// [mapboxId] (reusing the same session token) to get the full place and its
/// location.
class SearchSuggestion {
  SearchSuggestion({
    required this.mapboxId,
    required this.name,
    this.fullAddress,
    this.placeFormatted,
    this.distanceMeters,
    this.featureType,
  });

  static SearchSuggestion? fromJson(Map<String, dynamic> json) {
    final id = json['mapbox_id'] as String?;
    if (id == null) return null;
    return SearchSuggestion(
      mapboxId: id,
      name: (json['name'] ?? '').toString(),
      fullAddress: json['full_address'] as String?,
      placeFormatted: json['place_formatted'] as String?,
      distanceMeters: (json['distance'] as num?)?.toDouble(),
      featureType: json['feature_type'] as String?,
    );
  }

  /// Id to pass to `retrieve` to resolve the full place.
  final String mapboxId;

  /// Primary display name.
  final String name;

  /// Full address, when available.
  final String? fullAddress;

  /// Secondary line (city / region), when available.
  final String? placeFormatted;

  /// Distance from the `proximity` point in meters, when requested.
  final double? distanceMeters;

  /// Mapbox feature type (e.g. `address`, `poi`, `place`).
  final String? featureType;
}
