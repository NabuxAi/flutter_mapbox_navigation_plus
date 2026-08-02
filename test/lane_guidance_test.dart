import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lane guidance — which lanes exist at the junction ahead, and which of them
/// take the manoeuvre.
///
/// The v2 plugin got this for free from Mapbox's drop-in UI. v3 draws its own
/// chrome in Flutter, so the data has to reach Dart before anything can draw
/// it.
void main() {
  group('reading one lane', () {
    test('a usable lane carries its turns and says it is usable', () {
      final lane = LaneGuidance.fromJson(<dynamic, dynamic>{
        'directions': ['left', 'straight'],
        'active': true,
        'activeDirection': 'left',
      });

      expect(lane.directions, ['left', 'straight']);
      expect(lane.active, isTrue);
      expect(lane.activeDirection, 'left');
    });

    test('the arrow to draw is the manoeuvre when the banner named one', () {
      // A lane painted with two turns needs to highlight the one that takes
      // the manoeuvre, not whichever came first in the list.
      final lane = LaneGuidance.fromJson(<dynamic, dynamic>{
        'directions': ['straight', 'right'],
        'active': true,
        'activeDirection': 'right',
      });

      expect(lane.primaryDirection, 'right');
    });

    test('and its first turn when the banner did not', () {
      final lane = LaneGuidance.fromJson(<dynamic, dynamic>{
        'directions': ['straight'],
        'active': false,
        'activeDirection': '',
      });

      expect(lane.activeDirection, isNull);
      expect(lane.primaryDirection, 'straight');
    });

    test('a lane with nothing in it has no arrow rather than a crash', () {
      // Drawn while someone is driving. A row that arrives in an unexpected
      // shape must be one missing arrow, not an exception mid-manoeuvre.
      final lane = LaneGuidance.fromJson(<dynamic, dynamic>{});

      expect(lane.directions, isEmpty);
      expect(lane.active, isFalse);
      expect(lane.primaryDirection, isNull);
    });
  });

  group('on the progress event', () {
    test('lanes arrive with the rest of the progress', () {
      final progress = RouteProgressEvent.fromJson(<String, dynamic>{
        'arrived': false,
        'distance': 420.0,
        'duration': 61.0,
        'lanes': [
          <dynamic, dynamic>{
            'directions': ['left'],
            'active': true,
            'activeDirection': 'left',
          },
          <dynamic, dynamic>{
            'directions': ['straight'],
            'active': false,
            'activeDirection': '',
          },
        ],
      });

      expect(progress.lanes, hasLength(2));
      expect(progress.lanes.first.active, isTrue);
      expect(progress.lanes.last.active, isFalse);
    });

    test('away from a junction there are none, not a null', () {
      // Most of a route. A UI should be able to ask `isEmpty` without a null
      // check, and hide the strip rather than reserve space for it.
      final progress = RouteProgressEvent.fromJson(<String, dynamic>{
        'arrived': false,
        'distance': 4200.0,
      });

      expect(progress.lanes, isEmpty);
    });

    test('a malformed lane list is dropped, not thrown', () {
      final progress = RouteProgressEvent.fromJson(<String, dynamic>{
        'arrived': false,
        'lanes': 'not a list',
      });

      expect(progress.lanes, isEmpty);
    });
  });
}
