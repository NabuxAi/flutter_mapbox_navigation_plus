import Flutter
import UIKit
import CoreLocation
import MapboxMaps
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit

/// Shared base for the full-screen plugin and the embedded platform view.
///
/// Rewritten for Mapbox Navigation SDK v3: routing now goes through
/// `MapboxNavigationProvider.routingProvider().calculateRoutes(options:)`
/// (async), navigation is driven by `NavigationViewController(navigationRoutes:)`,
/// and progress/arrival/dismissal arrive through `NavigationViewControllerDelegate`.
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
            zoom: _zoom
        )
        freeDriveViewController.modalPresentationStyle = .fullScreen
        guard let host = UIApplication.shared.delegate?.window??.rootViewController else {
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
            let waypoint = Waypoint(
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
            let waypoint = Waypoint(
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude!, longitude: loc.longitude!),
                name: loc.name
            )
            waypoint.separatesLegs = !loc.isSilent
            _wayPoints.append(waypoint)
        }

        // v3 has no in-place "add a stop" call on a running session; recompute the
        // full route through the updated waypoint list and restart guidance.
        calculateAndPresent(wayPoints: _wayPoints, flutterResult: result)
    }

    // MARK: - Routing (v3 async)

    func calculateAndPresent(wayPoints: [Waypoint], flutterResult: @escaping FlutterResult)
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
                    self.presentNavigation(routes: navigationRoutes)
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

        guard let host = UIApplication.shared.delegate?.window??.rootViewController else { return }
        host.present(navigationViewController, animated: true, completion: nil)
    }

    /// Apply a custom day style URL to the navigation map, if one was supplied.
    func applyCustomStyleIfNeeded(to controller: NavigationViewController)
    {
        guard let styleUrl = _mapStyleUrlDay, let uri = StyleURI(rawValue: styleUrl) else { return }
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
        _options = options
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
        sendEvent(eventType: .on_arrival, data: "true")
    }

    public func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        if(canceled)
        {
            sendEvent(eventType: .navigation_cancelled)
        }
        endNavigation(result: nil)
    }
}
