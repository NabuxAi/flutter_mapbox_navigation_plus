import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('standard POI tap preserves structured feature data', () {
    final event = RouteEvent.fromJson({
      'eventType': 'standardPoiTapped',
      'data': {'name': 'Madina', 'group': 'landmark'},
    });

    expect(event.eventType, MapBoxEvent.standardPoiTapped);
    expect(
      event.data,
      {'name': 'Madina', 'group': 'landmark'},
    );
  });

  test('standard building tap preserves structured feature data', () {
    final event = RouteEvent.fromJson({
      'eventType': 'standardBuildingTapped',
      'data': <String, dynamic>{},
    });

    expect(event.eventType, MapBoxEvent.standardBuildingTapped);
    expect(event.data, isEmpty);
  });
}
