import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mapbox_navigation_plus/src/models/models.dart';

/// Controller for a single MapBox Navigation instance
/// running on the host platform.
class MapBoxNavigationViewController {
  /// Constructor
  MapBoxNavigationViewController(
    int id,
    ValueSetter<RouteEvent>? eventNotifier,
  ) {
    _methodChannel = MethodChannel('flutter_mapbox_navigation/$id');
    _methodChannel.setMethodCallHandler(_handleMethod);

    _eventChannel = EventChannel('flutter_mapbox_navigation/$id/events');
    _routeEventNotifier = eventNotifier;
  }

  late MethodChannel _methodChannel;
  late EventChannel _eventChannel;

  ValueSetter<RouteEvent>? _routeEventNotifier;

  StreamSubscription<RouteEvent>? _routeEventSubscription;

  ///Current Device OS Version
  Future<String> get platformVersion => _methodChannel
      .invokeMethod('getPlatformVersion')
      .then((dynamic result) => result as String);

  /// Check if the package is using Mapbox SDK V3 natively
  Future<bool> get isV3 => _methodChannel
      .invokeMethod('isV3')
      .then((dynamic result) => result as bool? ?? false)
      .catchError((_) => false);

  ///Total distance remaining in meters along route.
  Future<double> get distanceRemaining => _methodChannel
      .invokeMethod<double>('getDistanceRemaining')
      .then((dynamic result) => result as double);

  ///Total seconds remaining on all legs.
  Future<double> get durationRemaining => _methodChannel
      .invokeMethod<double>('getDurationRemaining')
      .then((dynamic result) => result as double);

  ///Build the Route Used for the Navigation
  ///
  /// [wayPoints] must not be null. A collection of [WayPoint](longitude,
  /// latitude and name). Must be at least 2 or at most 25. Cannot use
  /// drivingWithTraffic mode if more than 3-waypoints.
  /// [options] options used to generate the route and used while navigating
  ///
  Future<bool> buildRoute({
    required List<WayPoint> wayPoints,
    MapBoxOptions? options,
  }) async {
    assert(wayPoints.length > 1, 'Error: WayPoints must be at least 2');
    if (Platform.isIOS && wayPoints.length > 3 && options?.mode != null) {
      assert(
        options!.mode != MapBoxNavigationMode.drivingWithTraffic,
        '''
          Error: Cannot use drivingWithTraffic Mode 
          when you have more than 3 Stops
        ''',
      );
    }
    final pointList = <Map<String, Object?>>[];

    for (var i = 0; i < wayPoints.length; i++) {
      final wayPoint = wayPoints[i];
      assert(wayPoint.name != null, 'Error: waypoints need name');
      assert(wayPoint.latitude != null, 'Error: waypoints need latitude');
      assert(wayPoint.longitude != null, 'Error: waypoints need longitude');

      final pointMap = <String, dynamic>{
        'Order': i,
        'Name': wayPoint.name,
        'Latitude': wayPoint.latitude,
        'Longitude': wayPoint.longitude,
        'IsSilent': wayPoint.isSilent,
      };
      pointList.add(pointMap);
    }

    var i = 0;
    final wayPointMap = {for (final e in pointList) i++: e};

    var args = <String, dynamic>{};
    if (options != null) args = options.toMap();
    args['wayPoints'] = wayPointMap;

    _ensureRouteEventSubscription();
    return _methodChannel
        .invokeMethod('buildRoute', args)
        .then((dynamic result) => result as bool);
  }

  /// starts listening for events
  Future<void> initialize() async {
    _ensureRouteEventSubscription();
  }

  /// Adds one or more intermediate stops to the route that is currently shown
  /// or being navigated (Uber-style "add a stop"). The new [wayPoints] are
  /// appended and the route is recomputed; if a trip is active it continues
  /// along the updated route. Returns true on success.
  Future<bool> addWayPoints({required List<WayPoint> wayPoints}) async {
    assert(wayPoints.isNotEmpty, 'Error: WayPoints must not be empty');
    final pointList = <Map<String, Object?>>[];
    for (var i = 0; i < wayPoints.length; i++) {
      final wayPoint = wayPoints[i];
      assert(wayPoint.name != null, 'Error: waypoints need name');
      assert(wayPoint.latitude != null, 'Error: waypoints need latitude');
      assert(wayPoint.longitude != null, 'Error: waypoints need longitude');
      pointList.add(<String, dynamic>{
        'Order': i,
        'Name': wayPoint.name,
        'Latitude': wayPoint.latitude,
        'Longitude': wayPoint.longitude,
        'IsSilent': wayPoint.isSilent,
      });
    }
    var i = 0;
    final wayPointMap = {for (final e in pointList) i++: e};
    return _methodChannel
        .invokeMethod<bool>('addWayPoints', <String, dynamic>{
          'wayPoints': wayPointMap,
        })
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Clear the built route and resets the map
  Future<bool?> clearRoute() async {
    return _methodChannel.invokeMethod('clearRoute');
  }

  /// Starts Free Drive Mode
  Future<bool?> startFreeDrive({MapBoxOptions? options}) async {
    Map<String, dynamic>? args;
    if (options != null) args = options.toMap();
    return _methodChannel.invokeMethod('startFreeDrive', args);
  }

  /// Starts the Navigation
  Future<bool?> startNavigation({MapBoxOptions? options}) async {
    Map<String, dynamic>? args;
    if (options != null) args = options.toMap();
    //_routeEventSubscription = _streamRouteEvent.listen(_onProgressData);
    return _methodChannel.invokeMethod('startNavigation', args);
  }

  ///Ends Navigation and Closes the Navigation View
  Future<bool?> finishNavigation() async {
    final success = await _methodChannel.invokeMethod('finishNavigation');
    return success as bool?;
  }

  /// Recenter the navigation camera to following mode.
  Future<bool> recenter() async {
    return _methodChannel
        .invokeMethod<bool>('recenter')
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Toggle or set voice instructions state.
  /// If [enabled] is null, it toggles the current state.
  /// Returns the new state.
  Future<bool> toggleVoiceInstructions([bool? enabled]) async {
    return _methodChannel
        .invokeMethod<bool>('toggleVoiceInstructions', enabled)
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Adds (or replaces, by id) one or more [markers] on the map. Markers are
  /// rendered independently of the route, so you can show passengers, drivers,
  /// or points of interest. Returns true on success.
  Future<bool> addMarkers(List<MapMarker> markers) async {
    final args = <String, dynamic>{
      'markers': markers.map((m) => m.toMap()).toList(),
    };
    return _methodChannel
        .invokeMethod<bool>('addMarkers', args)
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Removes a single previously added marker by [id].
  Future<bool> removeMarker(String id) async {
    return _methodChannel
        .invokeMethod<bool>('removeMarker', <String, dynamic>{'id': id})
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Removes all markers added with [addMarkers].
  Future<bool> clearMarkers() async {
    return _methodChannel
        .invokeMethod<bool>('clearMarkers')
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Promotes the alternative route at [index] (as delivered by the
  /// `alternative_routes` event) to the primary route. Returns true on success.
  Future<bool> selectAlternativeRoute(int index) async {
    return _methodChannel
        .invokeMethod<bool>(
          'selectAlternativeRoute',
          <String, dynamic>{'index': index},
        )
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Moves the camera to the given target. By default the move is animated;
  /// pass `animate: false` for an instant jump. Omitted [zoom]/[bearing]/[tilt]
  /// keep their current value. This switches the camera out of the automatic
  /// navigation-following mode until [recenter]/[overview] is called.
  Future<bool> moveCamera({
    required double latitude,
    required double longitude,
    double? zoom,
    double? bearing,
    double? tilt,
    bool animate = true,
    int durationMs = 1000,
  }) async {
    return _methodChannel
        .invokeMethod<bool>('moveCamera', <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'zoom': zoom,
          'bearing': bearing,
          'tilt': tilt,
          'animate': animate,
          'durationMs': durationMs,
        })
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Frames the whole route (or the given bounds) in an overview camera.
  Future<bool> overview() async {
    return _methodChannel
        .invokeMethod<bool>('overview')
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Returns the current camera position, or null if unavailable.
  Future<CameraPosition?> getCameraPosition() async {
    final map = await _methodChannel
        .invokeMethod<Map<dynamic, dynamic>>('getCameraPosition');
    if (map == null) return null;
    return CameraPosition.fromMap(map);
  }

  /// Moves the camera so the given bounding box is visible, with [padding] in
  /// logical pixels on every edge.
  Future<bool> fitBounds({
    required double southwestLat,
    required double southwestLng,
    required double northeastLat,
    required double northeastLng,
    double padding = 40,
    bool animate = true,
  }) async {
    return _methodChannel
        .invokeMethod<bool>('fitBounds', <String, dynamic>{
          'southwestLat': southwestLat,
          'southwestLng': southwestLng,
          'northeastLat': northeastLat,
          'northeastLng': northeastLng,
          'padding': padding,
          'animate': animate,
        })
        .then((dynamic result) => result as bool? ?? false);
  }

  /// Generic Handler for Messages sent from the Platform
  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'sendFromNative':
        final text = call.arguments as String?;
        return Future.value('Text from native: $text');
    }
  }

  /// Call this to cancel the subscription to route events
  /// Add here future disposing methods
  void dispose() {
    final subscription = _routeEventSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _routeEventSubscription = null;
  }

  void _ensureRouteEventSubscription() {
    if (_routeEventSubscription != null) {
      return;
    }
    _routeEventSubscription = _streamRouteEvent!.listen(
      _onProgressData,
      // A single malformed payload must not surface as an unhandled async
      // error or stop navigation events for the rest of the session.
      onError: (Object error, StackTrace stackTrace) {},
      cancelOnError: false,
    );
  }

  void _onProgressData(RouteEvent event) {
    if (_routeEventNotifier != null) _routeEventNotifier?.call(event);
  }

  Stream<RouteEvent>? get _streamRouteEvent {
    return _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => _parseRouteEvent(event as String));
  }

  RouteEvent _parseRouteEvent(String jsonString) {
    RouteEvent event;
    final map = json.decode(jsonString) as Map<String, dynamic>;
    final progressEvent = RouteProgressEvent.fromJson(map);
    if (progressEvent.isProgressEvent ?? false) {
      event = RouteEvent(
        eventType: MapBoxEvent.progress_change,
        data: progressEvent,
      );
    } else {
      event = RouteEvent.fromJson(map);
    }
    return event;
  }
}
