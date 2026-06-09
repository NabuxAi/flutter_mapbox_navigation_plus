import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';

class SampleNavigationApp extends StatefulWidget {
  const SampleNavigationApp({super.key});

  @override
  State<SampleNavigationApp> createState() => _SampleNavigationAppState();
}

class _SampleNavigationAppState extends State<SampleNavigationApp> {
  String? _platformVersion;
  String? _instruction;
  final _origin = WayPoint(
      name: "Way Point 1",
      latitude: 38.9111117447887,
      longitude: -77.04012393951416,
      isSilent: true);
  final _stop1 = WayPoint(
      name: "Way Point 2",
      latitude: 38.91113678979344,
      longitude: -77.03847169876099,
      isSilent: true);
  final _stop2 = WayPoint(
      name: "Way Point 3",
      latitude: 38.91040213277608,
      longitude: -77.03848242759705,
      isSilent: false);
  final _stop3 = WayPoint(
      name: "Way Point 4",
      latitude: 38.909650771013034,
      longitude: -77.03850388526917,
      isSilent: true);
  final _destination = WayPoint(
      name: "Way Point 5",
      latitude: 38.90894949285854,
      longitude: -77.03651905059814,
      isSilent: false);

  final _home = WayPoint(
      name: "Home",
      latitude: 37.77440680146262,
      longitude: -122.43539772352648,
      isSilent: false);

  final _store = WayPoint(
      name: "Store",
      latitude: 37.76556957793795,
      longitude: -122.42409811526268,
      isSilent: false);

  bool _isMultipleStop = false;
  double? _distanceRemaining, _durationRemaining;
  double? _currentSpeed;
  String? _offlineStatus;

  // Map style switcher (recreates the embedded view with the chosen style).
  int _mapKey = 0;
  String _selectedStyle = 'Standard';
  static const Map<String, String?> _mapStyles = <String, String?>{
    'Standard': 'mapbox://styles/mapbox/standard',
    'Streets': 'mapbox://styles/mapbox/streets-v12',
    'Outdoors': 'mapbox://styles/mapbox/outdoors-v12',
    'Light': 'mapbox://styles/mapbox/light-v11',
    'Dark': 'mapbox://styles/mapbox/dark-v11',
    'Satellite': 'mapbox://styles/mapbox/satellite-v9',
    'Satellite Streets': 'mapbox://styles/mapbox/satellite-streets-v12',
    'Navigation Day': 'mapbox://styles/mapbox/navigation-day-v1',
    'Navigation Night': 'mapbox://styles/mapbox/navigation-night-v1',
  };

  MapBoxNavigationViewController? _controller;
  bool _routeBuilt = false;
  bool _isNavigating = false;
  bool _inFreeDrive = false;
  late MapBoxOptions _navigationOption;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initialize() async {
    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    _navigationOption = MapBoxNavigation.instance.getDefaultOptions();
    _navigationOption.simulateRoute = true;
    _navigationOption.language = "en";
    //_navigationOption.initialLatitude = 36.1175275;
    //_navigationOption.initialLongitude = -115.1839524;
    MapBoxNavigation.instance.registerRouteEventListener(_onEmbeddedRouteEvent);

    String? platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      platformVersion = await MapBoxNavigation.instance.getPlatformVersion();
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(
                      height: 10,
                    ),
                    Text('Running on: $_platformVersion\n'),
                    Container(
                      color: Colors.grey,
                      width: double.infinity,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: (Text(
                          "Full Screen Navigation",
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        )),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          child: const Text("Start A to B"),
                          onPressed: () async {
                            var wayPoints = <WayPoint>[];
                            wayPoints.add(_home);
                            wayPoints.add(_store);
                            var opt = MapBoxOptions.from(_navigationOption);
                            opt.simulateRoute = true;
                            opt.voiceInstructionsEnabled = true;
                            opt.bannerInstructionsEnabled = true;
                            opt.units = VoiceUnits.metric;
                            opt.language = "de-DE";
                            await MapBoxNavigation.instance.startNavigation(
                                wayPoints: wayPoints, options: opt);
                          },
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        ElevatedButton(
                          child: const Text("Start Multi Stop"),
                          onPressed: () async {
                            _isMultipleStop = true;
                            var wayPoints = <WayPoint>[];
                            wayPoints.add(_origin);
                            wayPoints.add(_stop1);
                            wayPoints.add(_stop2);
                            wayPoints.add(_stop3);
                            wayPoints.add(_destination);

                            MapBoxNavigation.instance.startNavigation(
                                wayPoints: wayPoints,
                                options: MapBoxOptions(
                                    mode: MapBoxNavigationMode.driving,
                                    simulateRoute: true,
                                    language: "en",
                                    allowsUTurnAtWayPoints: true,
                                    units: VoiceUnits.metric));
                            //after 10 seconds add a new stop
                            await Future.delayed(const Duration(seconds: 10));
                            var stop = WayPoint(
                                name: "Gas Station",
                                latitude: 38.911176544398,
                                longitude: -77.04014366543564,
                                isSilent: false);
                            MapBoxNavigation.instance
                                .addWayPoints(wayPoints: [stop]);
                          },
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        ElevatedButton(
                          child: const Text("Free Drive"),
                          onPressed: () async {
                            await MapBoxNavigation.instance.startFreeDrive();
                          },
                        ),
                      ],
                    ),
                    Container(
                      color: Colors.grey,
                      width: double.infinity,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: (Text(
                          "Embedded Navigation",
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        )),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: <Widget>[
                          const Text('Map style: '),
                          const SizedBox(width: 10),
                          DropdownButton<String>(
                            value: _selectedStyle,
                            items: _mapStyles.keys
                                .map((s) => DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(s),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedStyle = value;
                                _navigationOption.mapStyleUrlDay =
                                    _mapStyles[value];
                                _navigationOption.mapStyleUrlNight =
                                    _mapStyles[value];
                                // Force the embedded view to rebuild with the
                                // new style.
                                _mapKey++;
                                _routeBuilt = false;
                                _isNavigating = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _isNavigating
                              ? null
                              : () {
                                  if (_routeBuilt) {
                                    _controller?.clearRoute();
                                  } else {
                                    var wayPoints = <WayPoint>[];
                                    wayPoints.add(_home);
                                    wayPoints.add(_store);
                                    _isMultipleStop = wayPoints.length > 2;
                                    _controller?.buildRoute(
                                        wayPoints: wayPoints,
                                        options: _navigationOption);
                                  }
                                },
                          child: Text(_routeBuilt && !_isNavigating
                              ? "Clear Route"
                              : "Build Route"),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        ElevatedButton(
                          onPressed: _routeBuilt && !_isNavigating
                              ? () {
                                  _controller?.startNavigation();
                                }
                              : null,
                          child: const Text('Start '),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        ElevatedButton(
                          onPressed: _isNavigating
                              ? () {
                                  _controller?.finishNavigation();
                                }
                              : null,
                          child: const Text('Cancel '),
                        )
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _inFreeDrive
                          ? null
                          : () async {
                              _inFreeDrive =
                                  await _controller?.startFreeDrive() ?? false;
                            },
                      child: const Text("Free Drive "),
                    ),
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          "Long-Press Embedded Map to Set Destination",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Container(
                      color: Colors.grey,
                      width: double.infinity,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: (Text(
                          "Offline Maps & Routing (Android)",
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        )),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          child: const Text("Download"),
                          onPressed: () async {
                            // A box around the embedded A→B route (San Francisco).
                            final region = OfflineRegion.fromBounds(
                              id: 'sf-demo',
                              southWestLat: 37.75,
                              southWestLng: -122.45,
                              northEastLat: 37.79,
                              northEastLng: -122.42,
                              maxZoom: 14,
                            );
                            setState(() => _offlineStatus = 'Starting download…');
                            await MapBoxNavigation.instance
                                .downloadOfflineRegion(region);
                          },
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          child: const Text("List"),
                          onPressed: () async {
                            final regions = await MapBoxNavigation.instance
                                .getOfflineRegions();
                            setState(() => _offlineStatus =
                                'Downloaded regions: ${regions.join(', ')}');
                          },
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          child: const Text("Remove"),
                          onPressed: () async {
                            await MapBoxNavigation.instance
                                .removeOfflineRegion('sf-demo');
                          },
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        _offlineStatus ?? "Offline status here",
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Container(
                      color: Colors.grey,
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: (Text(
                          _instruction == null
                              ? "Banner Instruction Here"
                              : _instruction!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        )),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 20.0, right: 20, top: 20, bottom: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Text("Duration Remaining: "),
                              Text(_durationRemaining != null
                                  ? "${(_durationRemaining! / 60).toStringAsFixed(0)} minutes"
                                  : "---")
                            ],
                          ),
                          Row(
                            children: <Widget>[
                              const Text("Distance Remaining: "),
                              Text(_distanceRemaining != null
                                  ? "${(_distanceRemaining! * 0.000621371).toStringAsFixed(1)} miles"
                                  : "---")
                            ],
                          ),
                          Row(
                            children: <Widget>[
                              const Text("Current Speed: "),
                              Text(_currentSpeed != null
                                  ? "${(_currentSpeed! * 3.6).toStringAsFixed(0)} km/h"
                                  : "---")
                            ],
                          ),
                          Row(
                            children: <Widget>[
                              const Text("ETA: "),
                              Text(_durationRemaining != null
                                  ? DateTime.now()
                                      .add(Duration(
                                          seconds: _durationRemaining!.toInt()))
                                      .toLocal()
                                      .toString()
                                      .substring(11, 16)
                                  : "---")
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider()
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 300,
              child: Container(
                color: Colors.grey,
                child: MapBoxNavigationView(
                    key: ValueKey<int>(_mapKey),
                    options: _navigationOption,
                    onRouteEvent: _onEmbeddedRouteEvent,
                    onCreated:
                        (MapBoxNavigationViewController controller) async {
                      _controller = controller;
                      controller.initialize();
                    }),
              ),
            )
          ]),
        ),
      ),
    );
  }

  Future<void> _onEmbeddedRouteEvent(e) async {
    _distanceRemaining = await MapBoxNavigation.instance.getDistanceRemaining();
    _durationRemaining = await MapBoxNavigation.instance.getDurationRemaining();

    switch (e.eventType) {
      case MapBoxEvent.progress_change:
        var progressEvent = e.data as RouteProgressEvent;
        if (progressEvent.currentStepInstruction != null) {
          _instruction = progressEvent.currentStepInstruction;
        }
        _currentSpeed = progressEvent.currentSpeed;
        break;
      case MapBoxEvent.route_building:
      case MapBoxEvent.route_built:
        setState(() {
          _routeBuilt = true;
        });
        break;
      case MapBoxEvent.route_build_failed:
        setState(() {
          _routeBuilt = false;
        });
        break;
      case MapBoxEvent.navigation_running:
        setState(() {
          _isNavigating = true;
        });
        break;
      case MapBoxEvent.on_arrival:
        if (!_isMultipleStop) {
          await Future.delayed(const Duration(seconds: 3));
          await _controller?.finishNavigation();
        } else {}
        break;
      case MapBoxEvent.navigation_finished:
      case MapBoxEvent.navigation_cancelled:
        setState(() {
          _routeBuilt = false;
          _isNavigating = false;
        });
        break;
      case MapBoxEvent.offline_region_progress:
        final data = e.data as Map<String, dynamic>;
        final progress = (data['progress'] as num?)?.toDouble() ?? 0;
        _offlineStatus =
            'Downloading ${data['id']}: ${progress.toStringAsFixed(0)}%';
        break;
      case MapBoxEvent.offline_region_complete:
        final data = e.data as Map<String, dynamic>;
        _offlineStatus = 'Region ${data['id']} ready (offline)';
        break;
      case MapBoxEvent.offline_region_error:
        final data = e.data as Map<String, dynamic>;
        _offlineStatus = 'Offline error: ${data['message']}';
        break;
      case MapBoxEvent.offline_region_removed:
        final data = e.data as Map<String, dynamic>;
        _offlineStatus = 'Region ${data['id']} removed';
        break;
      default:
        break;
    }
    setState(() {});
  }
}
