import Flutter
import UIKit
import CoreLocation
import MapboxMaps
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit

/// `Waypoint` is declared in more than one imported Mapbox module under the v3
/// SDK, which makes the bare name ambiguous (the compiler can't read `[Waypoint]`
/// as a type). Pin it to the routing type used throughout the plugin.
public typealias Waypoint = MapboxDirections.Waypoint

extension UIApplication {
    /// Resolves the host view controller under both the legacy app-delegate
    /// window and the UIScene lifecycle. When the app adopts a
    /// `UIWindowSceneDelegate` (e.g. Flutter's `FlutterSceneDelegate`),
    /// `UIApplication.shared.delegate?.window` is nil, so navigation could never
    /// find a host and silently bailed out (tour/navigation never attached).
    /// Walk the connected scenes instead, falling back to the old path for
    /// non-scene apps.
    @MainActor
    var activeRootViewController: UIViewController? {
        let windowScenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first
        let window = activeScene?.windows.first { $0.isKeyWindow }
            ?? activeScene?.windows.first
        return window?.rootViewController ?? delegate?.window??.rootViewController
    }
}

/// Shared base for the full-screen plugin and the embedded platform view.
///
/// Marked `@MainActor`: the v3 SDK types it drives (`MapboxNavigation`,
/// `NavigationViewController`, `NavigationMapView`, UIKit) are main-actor
/// isolated, and Flutter delivers method/stream/platform-view callbacks on the
/// main thread, so the whole class belongs on the main actor.
@MainActor
public class NavigationFactory : NSObject, FlutterStreamHandler
{
    var _navigationViewController: NavigationViewController? = nil
    var _eventSink: FlutterEventSink? = nil

    let ALLOW_ROUTE_SELECTION = false
    let IsMultipleUniqueRoutes = false
    var isEmbeddedNavigation = false

    var _distanceRemaining: Double?
    var _durationRemaining: Double?
    // Emit navigation_running once per session instead of on every location
    // tick (consumers treat it as a state transition, not a heartbeat).
    var _navigationRunningNotified = false
    var _navigationMode: String?
    var _wayPoints = [Waypoint]()
    var _lastKnownLocation: CLLocation?

    var _options: NavigationRouteOptions?
    var _routes: NavigationRoutes?
    var _simulateRoute = false
    var _allowsUTurnAtWayPoints: Bool?
    var _isOptimized = false
    var _language = "en"
    var _voiceUnits = "imperial"
    var _mapStyleUrlDay: String?
    var _mapStyleUrlNight: String?
    var _zoom: Double = 13.0
    var _tilt: Double = 0.0
    var _bearing: Double = 0.0
    var _animateBuildRoute = true
    var _longPressDestinationEnabled = true
    var _alternatives = true
    var _shouldReRoute = true
    var _showReportFeedbackButton = true
    var _showEndOfRouteFeedback = true
    var _enableOnMapTapCallback = false
    var _voiceEnabled = true
    var _bannerEnabled = true
    var _padding: UIEdgeInsets = .zero
    var _exclude: [String] = []

    /// The single shared provider for routing + active guidance.
    var provider: MapboxNavigationProvider {
        NavigationProviderHolder.shared.provider(simulating: _simulateRoute)
    }
    var mapboxNavigation: MapboxNavigation { provider.mapboxNavigation }

    // MARK: - Full-screen entry points

    func startFreeDrive(arguments: NSDictionary?, result: @escaping FlutterResult)
    {
        parseFlutterArguments(arguments: arguments)
        let freeDriveViewController = FreeDriveViewController(
            provider: NavigationProviderHolder.shared.provider(simulating: _simulateRoute),
            mapStyleUrlDay: _mapStyleUrlDay,
            mapStyleUrlNight: _mapStyleUrlNight,
            zoom: _zoom
        )
        freeDriveViewController.modalPresentationStyle = .fullScreen
        guard let host = UIApplication.shared.activeRootViewController else {
            result(false)
            return
        }
        host.present(freeDriveViewController, animated: true, completion: nil)
        result(true)
    }

    func startNavigation(arguments: NSDictionary?, result: @escaping FlutterResult)
    {
        _wayPoints.removeAll()

        guard let locations = getLocationsFromFlutterArgument(arguments: arguments) else { return }

        for loc in locations
        {
            var waypoint = Waypoint(
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude!, longitude: loc.longitude!),
                name: loc.name
            )
            waypoint.separatesLegs = !loc.isSilent
            _wayPoints.append(waypoint)
        }

        parseFlutterArguments(arguments: arguments)

        if(_wayPoints.count > 3 && arguments?["mode"] == nil)
        {
            _navigationMode = "driving"
        }

        if(_wayPoints.count > 0)
        {
            calculateAndPresent(wayPoints: _wayPoints, flutterResult: result)
        }
    }

    func addWayPoints(arguments: NSDictionary?, result: @escaping FlutterResult)
    {
        guard let locations = getLocationsFromFlutterArgument(arguments: arguments) else { return }

        for loc in locations
        {
            var waypoint = Waypoint(
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude!, longitude: loc.longitude!),
                name: loc.name
            )
            waypoint.separatesLegs = !loc.isSilent
            _wayPoints.append(waypoint)
        }

        // Recompute the full route through the updated waypoint list. If a trip is
        // already running this updates it in place (see calculateAndPresent).
        calculateAndPresent(wayPoints: _wayPoints, isUpdate: true, flutterResult: result)
    }

    // MARK: - Routing (v3 async)

    func calculateAndPresent(wayPoints: [Waypoint], isUpdate: Bool = false, flutterResult: @escaping FlutterResult)
    {
        setNavigationOptions(wayPoints: wayPoints)
        guard let options = _options else {
            flutterResult(false)
            return
        }

        let request = mapboxNavigation.routingProvider().calculateRoutes(options: options)
        Task { [weak self] in
            guard let self = self else { return }
            let result = await request.result
            await MainActor.run {
                switch result {
                case .failure(let error):
                    self.sendEvent(eventType: .route_build_failed)
                    flutterResult("An error occured while calculating the route \(error.localizedDescription)")
                case .success(let navigationRoutes):
                    self._routes = navigationRoutes
                    self.sendAlternatives(routes: navigationRoutes)
                    if isUpdate, self._navigationViewController != nil {
                        // A trip is already on screen — update it in place instead
                        // of presenting a second NavigationViewController (which
                        // would fail with "already presenting").
                        self.mapboxNavigation.tripSession().startActiveGuidance(
                            with: navigationRoutes,
                            startLegIndex: 0
                        )
                    } else {
                        self.presentNavigation(routes: navigationRoutes)
                    }
                    flutterResult(true)
                }
            }
        }
    }

    func presentNavigation(routes: NavigationRoutes)
    {
        isEmbeddedNavigation = false
        let navigationOptions = NavigationOptions(
            mapboxNavigation: mapboxNavigation,
            voiceController: provider.routeVoiceController,
            eventsManager: provider.eventsManager()
        )

        let navigationViewController = NavigationViewController(
            navigationRoutes: routes,
            navigationOptions: navigationOptions
        )
        navigationViewController.modalPresentationStyle = .fullScreen
        navigationViewController.delegate = self
        navigationViewController.showsReportFeedback = _showReportFeedbackButton
        navigationViewController.showsEndOfRouteFeedback = _showEndOfRouteFeedback
        applyCustomStyleIfNeeded(to: navigationViewController)

        _navigationViewController = navigationViewController
        _navigationRunningNotified = false

        guard let host = UIApplication.shared.activeRootViewController else { return }
        host.present(navigationViewController, animated: true, completion: nil)
    }

    /// Pick the custom style URL to apply for the given appearance: the night
    /// style in dark mode when one is configured, otherwise the day style.
    func resolvedMapStyleUrl(for traitCollection: UITraitCollection) -> String? {
        if traitCollection.userInterfaceStyle == .dark,
           let night = _mapStyleUrlNight, !night.isEmpty {
            return night
        }
        return _mapStyleUrlDay
    }

    /// Apply the custom day/night style URL to the navigation map, if supplied.
    func applyCustomStyleIfNeeded(to controller: NavigationViewController)
    {
        guard let styleUrl = resolvedMapStyleUrl(for: controller.traitCollection),
              let uri = StyleURI(rawValue: styleUrl) else { return }
        controller.navigationMapView?.mapView.mapboxMap.mapStyle = MapStyle(uri: uri)
    }

    func setNavigationOptions(wayPoints: [Waypoint]) {
        var mode: ProfileIdentifier = .automobileAvoidingTraffic

        if (_navigationMode == "cycling")
        {
            mode = .cycling
        }
        else if(_navigationMode == "driving")
        {
            mode = .automobile
        }
        else if(_navigationMode == "walking")
        {
            mode = .walking
        }
        let options = NavigationRouteOptions(waypoints: wayPoints, profileIdentifier: mode)

        if (_allowsUTurnAtWayPoints != nil)
        {
            options.allowsUTurnAtWaypoint = _allowsUTurnAtWayPoints!
        }

        options.distanceMeasurementSystem = _voiceUnits == "imperial" ? .imperial : .metric
        options.locale = Locale(identifier: _language)
        options.includesAlternativeRoutes = _alternatives
        options.roadClassesToAvoid = roadClassesToAvoid(from: _exclude)
        _options = options
    }

    /// Maps the Dart `exclude` strings (toll, motorway, ferry, ...) to the
    /// MapboxDirections `RoadClasses` option set used by the routing request.
    func roadClassesToAvoid(from exclude: [String]) -> RoadClasses {
        var classes: RoadClasses = []
        for value in exclude {
            switch value.lowercased() {
            case "toll", "cash_only_tolls": classes.insert(.toll)
            case "motorway": classes.insert(.motorway)
            case "ferry": classes.insert(.ferry)
            case "tunnel": classes.insert(.tunnel)
            case "restricted": classes.insert(.restricted)
            default: break
            }
        }
        return classes
    }

    func parseFlutterArguments(arguments: NSDictionary?) {
        _language = arguments?["language"] as? String ?? _language
        _voiceUnits = arguments?["units"] as? String ?? _voiceUnits
        _simulateRoute = arguments?["simulateRoute"] as? Bool ?? _simulateRoute
        _isOptimized = arguments?["isOptimized"] as? Bool ?? _isOptimized
        _allowsUTurnAtWayPoints = arguments?["allowsUTurnAtWayPoints"] as? Bool
        _navigationMode = arguments?["mode"] as? String ?? "drivingWithTraffic"
        _showReportFeedbackButton = arguments?["showReportFeedbackButton"] as? Bool ?? _showReportFeedbackButton
        _showEndOfRouteFeedback = arguments?["showEndOfRouteFeedback"] as? Bool ?? _showEndOfRouteFeedback
        _enableOnMapTapCallback = arguments?["enableOnMapTapCallback"] as? Bool ?? _enableOnMapTapCallback
        _voiceEnabled = arguments?["voiceInstructionsEnabled"] as? Bool ?? true
        _bannerEnabled = arguments?["bannerInstructionsEnabled"] as? Bool ?? true
        _mapStyleUrlDay = arguments?["mapStyleUrlDay"] as? String
        _mapStyleUrlNight = arguments?["mapStyleUrlNight"] as? String
        _zoom = arguments?["zoom"] as? Double ?? _zoom
        _bearing = arguments?["bearing"] as? Double ?? _bearing
        _tilt = arguments?["tilt"] as? Double ?? _tilt
        _animateBuildRoute = arguments?["animateBuildRoute"] as? Bool ?? _animateBuildRoute
        _longPressDestinationEnabled = arguments?["longPressDestinationEnabled"] as? Bool ?? _longPressDestinationEnabled
        _alternatives = arguments?["alternatives"] as? Bool ?? _alternatives
        if let exclude = arguments?["exclude"] as? [String] {
            _exclude = exclude
        }

        if let padding = arguments?["padding"] as? [Double], padding.count == 4 {
            _padding = UIEdgeInsets(top: CGFloat(padding[0]), left: CGFloat(padding[1]), bottom: CGFloat(padding[2]), right: CGFloat(padding[3]))
        }
    }

    func endNavigation(result: FlutterResult?)
    {
        _navigationRunningNotified = false
        sendEvent(eventType: .navigation_finished)
        // Stop the data flow / billing session.
        mapboxNavigation.tripSession().setToIdle()

        if(self._navigationViewController != nil)
        {
            if(isEmbeddedNavigation)
            {
                self._navigationViewController?.view.removeFromSuperview()
                self._navigationViewController?.removeFromParent()
                self._navigationViewController = nil
                if let result = result { result(true) }
            }
            else
            {
                self._navigationViewController?.dismiss(animated: true, completion: {
                    self._navigationViewController = nil
                    if let result = result { result(true) }
                })
            }
        }
        else if let result = result {
            result(true)
        }
    }

    // MARK: - Argument helpers

    func getLocationsFromFlutterArgument(arguments: NSDictionary?) -> [Location]? {

        var locations = [Location]()
        guard let oWayPoints = arguments?["wayPoints"] as? NSDictionary else {return nil}
        for item in oWayPoints as NSDictionary
        {
            let point = item.value as! NSDictionary
            guard let oName = point["Name"] as? String else {return nil }
            guard let oLatitude = point["Latitude"] as? Double else {return nil}
            guard let oLongitude = point["Longitude"] as? Double else {return nil}
            let oIsSilent = point["IsSilent"] as? Bool ?? false
            let order = point["Order"] as? Int
            let location = Location(name: oName, latitude: oLatitude, longitude: oLongitude, order: order, isSilent: oIsSilent)
            locations.append(location)
        }
        if(!_isOptimized)
        {
            //waypoints must be in the right order
            locations.sort(by: {$0.order ?? 0 < $1.order ?? 0})
        }
        return locations
    }

    // MARK: - Events

    func sendEvent(eventType: MapBoxEventType, data: String = "")
    {
        let routeEvent = MapBoxRouteEvent(eventType: eventType, data: data)

        let jsonEncoder = JSONEncoder()
        let jsonData = try! jsonEncoder.encode(routeEvent)
        let eventJson = String(data: jsonData, encoding: String.Encoding.utf8)
        if(_eventSink != nil){
            _eventSink!(eventJson)
        }
    }

    /// Emit an event whose `data` is a JSON object (used by the offline manager
    /// for parity with the Android `offline_region_*` payloads).
    func sendObjectEvent(eventType: String, data: [String: Any])
    {
        let payload: [String: Any] = ["eventType": eventType, "data": data]
        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        if let sink = _eventSink {
            sink(json)
        }
    }

    /// Emit an event whose `data` is a JSON array (parity with the Android
    /// `alternative_routes` payload).
    func sendArrayEvent(eventType: String, data: [[String: Any]])
    {
        let payload: [String: Any] = ["eventType": eventType, "data": data]
        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        if let sink = _eventSink {
            sink(json)
        }
    }

    /// Emit a summary (index / distance / duration) of every route returned by a
    /// build request so a Flutter UI can present the alternatives.
    func sendAlternatives(routes: NavigationRoutes)
    {
        var list: [[String: Any]] = []
        let main = routes.mainRoute.route
        list.append([
            "index": 0,
            "distance": main.distance,
            "duration": main.expectedTravelTime,
            "isPrimary": true,
            "geometry": routeGeometry(main),
        ])
        for (offset, alternative) in routes.alternativeRoutes.enumerated() {
            let route = alternative.route
            list.append([
                "index": offset + 1,
                "distance": route.distance,
                "duration": route.expectedTravelTime,
                "isPrimary": false,
                "geometry": routeGeometry(route),
            ])
        }
        sendArrayEvent(eventType: "alternative_routes", data: list)
    }

    /// A route's geometry as a list of [lat, lng] pairs for Dart.
    func routeGeometry(_ route: Route) -> [[Double]] {
        return route.shape?.coordinates.map { [$0.latitude, $0.longitude] } ?? []
    }

    /// Whether `waypoint` is the final destination (vs an intermediate stop).
    func isFinalWaypoint(_ waypoint: Waypoint) -> Bool {
        guard let last = _wayPoints.last else { return true }
        return abs(last.coordinate.latitude - waypoint.coordinate.latitude) < 1e-6
            && abs(last.coordinate.longitude - waypoint.coordinate.longitude) < 1e-6
    }

    func encodeRouteResponse(routes: NavigationRoutes) -> String {
        let jsonEncoder = JSONEncoder()
        // The primary route is enough for consumers that decode route geometry.
        if let jsonData = try? jsonEncoder.encode([routes.mainRoute.route]) {
            return String(data: jsonData, encoding: String.Encoding.utf8) ?? "{}"
        }
        return "{}"
    }

    //MARK: EventListener Delegates
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        _eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        _eventSink = nil
        return nil
    }
}

extension NavigationFactory : NavigationViewControllerDelegate {
    //MARK: NavigationViewController Delegates
    public func navigationViewController(_ navigationViewController: NavigationViewController, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
        _lastKnownLocation = location
        _distanceRemaining = progress.distanceRemaining
        _durationRemaining = progress.durationRemaining
        if (!_navigationRunningNotified)
        {
            _navigationRunningNotified = true
            sendEvent(eventType: .navigation_running)
        }
        sendObjectEvent(eventType: "location_change", data: [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "bearing": location.course,
            "speed": max(location.speed, 0),
        ])
        if(_eventSink != nil)
        {
            let jsonEncoder = JSONEncoder()

            let progressEvent = MapBoxRouteProgressEvent(progress: progress, currentSpeed: location.speed)
            let progressEventJsonData = try! jsonEncoder.encode(progressEvent)
            // UTF-8: non-ASCII instruction text (Arabic, Persian, ...) made the
            // .ascii encoder return nil and silently killed the event stream.
            let progressEventJson = String(data: progressEventJsonData, encoding: String.Encoding.utf8)

            _eventSink!(progressEventJson)
        }
    }

    public func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) {
        if isFinalWaypoint(waypoint) {
            sendEvent(eventType: .on_arrival, data: "true")
        } else {
            sendObjectEvent(eventType: "waypoint_arrival", data: ["name": waypoint.name ?? ""])
        }
    }

    public func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        if(canceled)
        {
            sendEvent(eventType: .navigation_cancelled)
        }
        endNavigation(result: nil)
    }
}
