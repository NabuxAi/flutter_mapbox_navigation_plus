import 'package:flutter/material.dart';
import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';

/// A fully custom Flutter turn-by-turn UI built on top of the embedded
/// [MapBoxNavigationView].
///
/// Everything you see over the map — the maneuver card, the ETA/speed panel,
/// the alternative-route chips and the action buttons — is plain Flutter,
/// driven entirely by the plugin's route events and controller methods. This is
/// the recommended pattern when you want your own branding instead of the
/// SDK's built-in navigation UI.
class CustomNavUiPage extends StatefulWidget {
  const CustomNavUiPage({super.key});

  @override
  State<CustomNavUiPage> createState() => _CustomNavUiPageState();
}

class _CustomNavUiPageState extends State<CustomNavUiPage> {
  static final _origin = WayPoint(
    name: 'Home',
    latitude: 37.77440680146262,
    longitude: -122.43539772352648,
  );
  static final _destination = WayPoint(
    name: 'Store',
    latitude: 37.76556957793795,
    longitude: -122.42409811526268,
  );
  static final _extraStop = WayPoint(
    name: 'Coffee',
    latitude: 37.7705,
    longitude: -122.4300,
  );

  MapBoxNavigationViewController? _controller;
  late final MapBoxOptions _options;

  bool _routeBuilt = false;
  bool _navigating = false;
  bool _voiceOn = true;

  RouteProgressEvent? _progress;
  List<RouteAlternative> _alternatives = const [];
  int _selectedRoute = 0;

  @override
  void initState() {
    super.initState();
    _options = MapBoxOptions(
      initialLatitude: _origin.latitude,
      initialLongitude: _origin.longitude,
      zoom: 13,
      mode: MapBoxNavigationMode.drivingWithTraffic,
      simulateRoute: true,
      alternatives: true,
      voiceInstructionsEnabled: true,
      units: VoiceUnits.metric,
      language: 'en',
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _buildRoute() async {
    await _controller?.buildRoute(
      wayPoints: [_origin, _destination],
      options: _options,
    );
    // Drop a branded destination marker — independent of the route line.
    await _controller?.addMarkers([
      MapMarker(
        id: 'destination',
        latitude: _destination.latitude!,
        longitude: _destination.longitude!,
        label: 'Store',
        color: '#1A73E8',
        radius: 9,
      ),
    ]);
  }

  Future<void> _onRouteEvent(RouteEvent e) async {
    switch (e.eventType) {
      case MapBoxEvent.route_built:
        setState(() => _routeBuilt = true);
        break;
      case MapBoxEvent.route_build_failed:
        setState(() => _routeBuilt = false);
        break;
      case MapBoxEvent.alternative_routes:
        setState(() => _alternatives = e.data as List<RouteAlternative>);
        break;
      case MapBoxEvent.navigation_running:
        setState(() => _navigating = true);
        break;
      case MapBoxEvent.progress_change:
        setState(() => _progress = e.data as RouteProgressEvent);
        break;
      case MapBoxEvent.on_arrival:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You have arrived 🎉')),
          );
        }
        break;
      case MapBoxEvent.navigation_finished:
      case MapBoxEvent.navigation_cancelled:
        setState(() {
          _navigating = false;
          _routeBuilt = false;
          _progress = null;
          _alternatives = const [];
        });
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Navigation UI')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapBoxNavigationView(
              options: _options,
              onRouteEvent: _onRouteEvent,
              onCreated: (controller) async {
                _controller = controller;
                await controller.initialize();
              },
            ),
          ),
          if (_navigating) _maneuverCard(),
          if (_routeBuilt && !_navigating && _alternatives.length > 1)
            _alternativesBar(),
          _bottomPanel(),
        ],
      ),
    );
  }

  // ---- Overlays -------------------------------------------------------------

  Widget _maneuverCard() {
    final p = _progress;
    final instruction = p?.currentStepInstruction?.isNotEmpty ?? false
        ? p!.currentStepInstruction!
        : 'Continue';
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Card(
        color: const Color(0xFF1A73E8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                _maneuverIcon(p?.maneuverType, p?.maneuverModifier),
                color: Colors.white,
                size: 40,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (p?.upcomingInstruction?.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Then: ${p!.upcomingInstruction}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alternativesBar() {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _alternatives.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final r = _alternatives[i];
            final mins = (r.duration / 60).round();
            final km = (r.distance / 1000).toStringAsFixed(1);
            return ChoiceChip(
              label: Text('$mins min · $km km'),
              selected: _selectedRoute == i,
              onSelected: (_) async {
                await _controller?.selectAlternativeRoute(r.index);
                setState(() => _selectedRoute = i);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _bottomPanel() {
    final p = _progress;
    final etaText = p?.duration != null && p!.duration! > 0
        ? TimeOfDay.fromDateTime(
            DateTime.now().add(Duration(seconds: p.duration!.round())),
          ).format(context)
        : '--:--';
    final distKm =
        p?.distance != null ? (p!.distance! / 1000).toStringAsFixed(1) : '--';
    final durMin =
        p?.duration != null ? (p!.duration! / 60).round().toString() : '--';
    final speedKmh = p?.currentSpeed != null
        ? (p!.currentSpeed! * 3.6).round().toString()
        : '0';
    final speedLimit =
        p?.speedLimit != null ? '${p!.speedLimit!.round()}' : '--';

    return Align(
      alignment: Alignment.bottomCenter,
      child: Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('ETA', etaText),
                  _stat('Distance', '$distKm km'),
                  _stat('Time', '$durMin min'),
                  _stat('Speed', '$speedKmh km/h'),
                  _stat('Limit', speedLimit),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (!_routeBuilt)
                    FilledButton.icon(
                      onPressed: _buildRoute,
                      icon: const Icon(Icons.alt_route),
                      label: const Text('Build route'),
                    ),
                  if (_routeBuilt && !_navigating)
                    FilledButton.icon(
                      onPressed: () => _controller?.startNavigation(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                    ),
                  if (_navigating) ...[
                    OutlinedButton.icon(
                      onPressed: () =>
                          _controller?.addWayPoints(wayPoints: [_extraStop]),
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Add stop'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _controller?.recenter(),
                      icon: const Icon(Icons.my_location),
                      label: const Text('Recenter'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final on =
                            await _controller?.toggleVoiceInstructions() ??
                                _voiceOn;
                        setState(() => _voiceOn = on);
                      },
                      icon: Icon(_voiceOn ? Icons.volume_up : Icons.volume_off),
                      label: Text(_voiceOn ? 'Mute' : 'Unmute'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _controller?.finishNavigation(),
                      icon: const Icon(Icons.close),
                      label: const Text('End'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  /// Maps a Mapbox maneuver type/modifier to a Material turn icon for the card.
  IconData _maneuverIcon(String? type, String? modifier) {
    switch (type) {
      case 'arrive':
        return Icons.place;
      case 'depart':
        return Icons.my_location;
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn':
        return Icons.roundabout_left;
      case 'merge':
        return Icons.merge;
    }
    switch (modifier) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return Icons.turn_left;
      case 'right':
      case 'slight right':
      case 'sharp right':
        return Icons.turn_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'straight':
      default:
        return Icons.straight;
    }
  }
}
