/// One lane of the road, as the navigation banner describes it.
///
/// Approaching a junction, the Directions API sends a sub-banner listing the
/// lanes left to right, which turns are painted in each, and which of them can
/// be used for the manoeuvre coming up. Drivers use it to get into the right
/// lane before the turn rather than at it.
///
/// The list is empty for most of a route: lanes only arrive approaching a
/// junction that has them.
class LaneGuidance {
  /// Creates lane guidance for a single lane.
  const LaneGuidance({
    this.directions = const [],
    this.active = false,
    this.activeDirection,
  });

  /// Reads one lane off the platform channel.
  ///
  /// Tolerant on purpose — this is drawn while someone is driving, and a lane
  /// row that arrives in an unexpected shape should be one missing arrow, not
  /// a thrown exception in the middle of a manoeuvre.
  factory LaneGuidance.fromJson(Map<dynamic, dynamic> json) {
    final directions = json['directions'];

    return LaneGuidance(
      directions: directions is List
          ? directions.map((dynamic e) => '$e').toList()
          : const [],
      active: json['active'] == true,
      activeDirection:
          (json['activeDirection'] as String?)?.trim().isEmpty ?? true
              ? null
              : json['activeDirection'] as String?,
    );
  }

  /// Turns painted in this lane: `left`, `right`, `straight`, `slight left`,
  /// `sharp right`, `uturn`, and so on. A lane can carry more than one.
  final List<String> directions;

  /// Whether this lane can be used for the manoeuvre being approached.
  ///
  /// The one field that matters to a driver: the usable lanes are the ones to
  /// be in.
  final bool active;

  /// Which of [directions] to highlight when the lane carries several — the
  /// one that takes the manoeuvre. Null when the banner did not say.
  final String? activeDirection;

  /// The arrow to draw for this lane: the manoeuvre's direction when the
  /// banner named one, otherwise the lane's first painted turn.
  String? get primaryDirection =>
      activeDirection ?? (directions.isEmpty ? null : directions.first);

  @override
  String toString() => 'LaneGuidance(directions: $directions, active: $active, '
      'activeDirection: $activeDirection)';
}
