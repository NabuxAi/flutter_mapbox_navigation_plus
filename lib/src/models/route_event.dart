import 'dart:convert';
import 'dart:io';

import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';

/// Represents an event sent by the navigation service
class RouteEvent {
  /// Constructor
  RouteEvent({
    this.eventType,
    this.data,
  });

  /// Creates [RouteEvent] object from json
  RouteEvent.fromJson(Map<String, dynamic> json) {
    try {
      eventType = MapBoxEvent.values
          .firstWhere((e) => e.toString().split('.').last == json['eventType']);
    } catch (_) {}

    final dataJson = json['data'];
    if (eventType == MapBoxEvent.progress_change &&
        dataJson is Map<String, dynamic>) {
      data = RouteProgressEvent.fromJson(dataJson);
    } else if (eventType == MapBoxEvent.navigation_finished &&
        dataJson is String &&
        dataJson.isNotEmpty) {
      // Android sends navigation_finished without a data payload; only iOS
      // attaches optional end-of-route feedback JSON.
      data =
          MapBoxFeedback.fromJson(jsonDecode(dataJson) as Map<String, dynamic>);
    } else if (eventType == MapBoxEvent.on_map_tap) {
      final json =
          Platform.isAndroid ? dataJson : jsonDecode(dataJson as String);
      data = WayPoint.fromJson(json as Map<String, dynamic>);
    } else if (eventType == MapBoxEvent.standardPoiTapped ||
        eventType == MapBoxEvent.standardBuildingTapped ||
        eventType == MapBoxEvent.camera_state_changed ||
        eventType == MapBoxEvent.offline_region_progress ||
        eventType == MapBoxEvent.offline_region_complete ||
        eventType == MapBoxEvent.offline_region_error ||
        eventType == MapBoxEvent.offline_region_removed ||
        eventType == MapBoxEvent.waypoint_arrival) {
      data = dataJson as Map<String, dynamic>?;
    } else if (eventType == MapBoxEvent.alternative_routes) {
      data = RouteAlternative.listFromJson(dataJson);
    } else {
      data = jsonEncode(dataJson);
    }
  }

  /// Route event type
  MapBoxEvent? eventType;

  /// optional data related to route event
  dynamic data;
}
