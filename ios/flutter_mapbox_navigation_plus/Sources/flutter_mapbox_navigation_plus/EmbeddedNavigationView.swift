import Flutter
import UIKit
import Combine
import CoreLocation
import MapboxMaps
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit

public class FlutterMapboxNavigationView : NavigationFactory, FlutterPlatformView
{
    let frame: CGRect
    let viewId: Int64

    let messenger: FlutterBinaryMessenger
    let channel: FlutterMethodChannel
    let eventChannel: FlutterEventChannel

    var navigationMapView: NavigationMapView!
    var arguments: NSDictionary?

    var _mapInitialized = false
    var locationManager = CLLocationManager()

    init(messenger: FlutterBinaryMessenger, frame: CGRect, viewId: Int64, args: Any?)
    {
        self.frame = frame
        self.viewId = viewId
        self.arguments = args as! NSDictionary?

        self.messenger = messenger
        self.channel = FlutterMethodChannel(name: "flutter_mapbox_navigation/\(viewId)", binaryMessenger: messenger)
        self.eventChannel = FlutterEventChannel(name: "flutter_mapbox_navigation/\(viewId)/events", binaryMessenger: messenger)

        super.init()

        self.eventChannel.setStreamHandler(self)

        self.channel.setMethodCallHandler { [weak self](call, result) in

            guard let strongSelf = self else { return }

            let arguments = call.arguments as? NSDictionary

            switch call.method {
            case "getPlatformVersion":
                result("iOS " + UIDevice.current.systemVersion)
            case "buildRoute":
                strongSelf.buildRoute(arguments: arguments, flutterResult: result)
            case "clearRoute":
                strongSelf.clearRoute(arguments: arguments, result: result)
            case "getDistanceRemaining":
                result(strongSelf._distanceRemaining)
            case "getDurationRemaining":
                result(strongSelf._durationRemaining)
            case "isV3":
                // The iOS implementation now embeds the Navigation SDK v3 native
                // turn-by-turn UI, on par with Android.
                result(true)
            case "finishNavigation":
                strongSelf.endNavigation(result: result)
            case "startFreeDrive":
                strongSelf.startEmbeddedFreeDrive(arguments: arguments, result: result)
            case "startNavigation":
                strongSelf.startEmbeddedNavigation(arguments: arguments, result: result)
            case "recenter", "reCenter":
                strongSelf.recenterEmbeddedCamera()
                result(true)
            case "toggleVoiceInstructions":
                let requested = call.arguments as? Bool
                result(strongSelf.toggleEmbeddedVoiceInstructions(requested))
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    public func view() -> UIView
    {
        if(_mapInitialized)
        {
            return navigationMapView
        }

        setupMapView()

        return navigationMapView
    }

    private func setupMapView()
    {
        if(self.arguments != nil)
        {
            parseFlutterArguments(arguments: arguments)
        }

        let nav = mapboxNavigation
        navigationMapView = NavigationMapView(
            location: nav.navigation().locationMatching.map(\.enhancedLocation).eraseToAnyPublisher(),
            routeProgress: nav.navigation().routeProgress.map(\.?.routeProgress).eraseToAnyPublisher(),
            predictiveCacheManager: provider.predictiveCacheManager
        )
        navigationMapView.frame = frame
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        _mapInitialized = true

        if let styleUrl = _mapStyleUrlDay, let uri = StyleURI(rawValue: styleUrl) {
            navigationMapView.mapView.mapboxMap.mapStyle = MapStyle(uri: uri)
        }

        locationManager.requestWhenInUseAuthorization()
        // Begin passive location updates so the puck follows the user.
        nav.tripSession().startFreeDrive()

        if _longPressDestinationEnabled
        {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            gesture.delegate = self
            navigationMapView?.addGestureRecognizer(gesture)
        }

        if _enableOnMapTapCallback {
            let onTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            onTapGesture.numberOfTapsRequired = 1
            onTapGesture.delegate = self
            navigationMapView?.addGestureRecognizer(onTapGesture)
        }
    }

    func clearRoute(arguments: NSDictionary?, result: @escaping FlutterResult)
    {
        if _routes == nil
        {
            result(false)
            return
        }
        mapboxNavigation.tripSession().setToIdle()
        navigationMapView?.removeRoutes()
        _routes = nil
        sendEvent(eventType: .navigation_cancelled)
        result(true)
    }

    func buildRoute(arguments: NSDictionary?, flutterResult: @escaping FlutterResult)
    {
        _wayPoints.removeAll()
        isEmbeddedNavigation = true
        sendEvent(eventType: .route_building)

        parseFlutterArguments(arguments: arguments)

        guard let locations = getLocationsFromFlutterArgument(arguments: arguments) else {
            flutterResult(false)
            sendEvent(eventType: .route_build_failed)
            return
        }

        for loc in locations
        {
            var waypoint = Waypoint(
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude!, longitude: loc.longitude!),
                name: loc.name
            )
            waypoint.separatesLegs = !loc.isSilent
            _wayPoints.append(waypoint)
        }

        if(_wayPoints.count > 3 && arguments?["mode"] == nil)
        {
            _navigationMode = "driving"
        }

        setNavigationOptions(wayPoints: _wayPoints)
        guard let options = _options else {
            flutterResult(false)
            sendEvent(eventType: .route_build_failed)
            return
        }

        let request = mapboxNavigation.routingProvider().calculateRoutes(options: options)
        Task { [weak self] in
            guard let self = self else { return }
            let result = await request.result
            await MainActor.run {
                switch result {
                case .failure:
                    self.sendEvent(eventType: .route_build_failed)
                    flutterResult(false)
                case .success(let navigationRoutes):
                    self._routes = navigationRoutes
                    self.sendEvent(eventType: .route_built, data: self.encodeRouteResponse(routes: navigationRoutes))
                    // showcase draws the route lines + waypoint markers and frames them.
                    self.navigationMapView?.showcase(navigationRoutes)
                    flutterResult(true)
                }
            }
        }
    }

    func startEmbeddedFreeDrive(arguments: NSDictionary?, result: @escaping FlutterResult) {
        parseFlutterArguments(arguments: arguments)
        mapboxNavigation.tripSession().startFreeDrive()
        navigationMapView?.navigationCamera.update(cameraState: .following)
        result(true)
    }

    func startEmbeddedNavigation(arguments: NSDictionary?, result: @escaping FlutterResult) {
        guard let routes = self._routes else {
            result(false)
            return
        }

        let navigationOptions = NavigationOptions(
            mapboxNavigation: mapboxNavigation,
            voiceController: provider.routeVoiceController,
            eventsManager: provider.eventsManager()
        )

        // Remove a previous navigation controller if any.
        if(_navigationViewController?.view != nil){
            _navigationViewController!.view.removeFromSuperview()
            _navigationViewController?.removeFromParent()
        }

        let navigationViewController = NavigationViewController(
            navigationRoutes: routes,
            navigationOptions: navigationOptions
        )
        navigationViewController.delegate = self
        navigationViewController.showsReportFeedback = _showReportFeedbackButton
        navigationViewController.showsEndOfRouteFeedback = _showEndOfRouteFeedback
        _navigationViewController = navigationViewController

        // Any root view controller can host the child.
        guard let hostViewController = UIApplication.shared.delegate?.window??.rootViewController else {
            result(false)
            return
        }
        hostViewController.addChild(navigationViewController)
        self.navigationMapView.addSubview(navigationViewController.view)
        navigationViewController.view.translatesAutoresizingMaskIntoConstraints = false
        constraintsWithPaddingBetween(holderView: self.navigationMapView, topView: navigationViewController.view, padding: 0.0)
        navigationViewController.didMove(toParent: hostViewController)
        _navigationRunningNotified = false
        result(true)
    }

    func recenterEmbeddedCamera() {
        navigationMapView?.navigationCamera.update(cameraState: .following)
        _navigationViewController?.navigationMapView?.navigationCamera.update(cameraState: .following)
    }

    func toggleEmbeddedVoiceInstructions(_ requested: Bool?) -> Bool {
        _voiceEnabled = requested ?? !_voiceEnabled
        return _voiceEnabled
    }

    func constraintsWithPaddingBetween(holderView: UIView, topView: UIView, padding: CGFloat) {
        guard holderView.subviews.contains(topView) else {
            return
        }
        topView.translatesAutoresizingMaskIntoConstraints = false
        let pinTop = NSLayoutConstraint(item: topView, attribute: .top, relatedBy: .equal,
                                        toItem: holderView, attribute: .top, multiplier: 1.0, constant: padding)
        let pinBottom = NSLayoutConstraint(item: topView, attribute: .bottom, relatedBy: .equal,
                                           toItem: holderView, attribute: .bottom, multiplier: 1.0, constant: padding)
        let pinLeft = NSLayoutConstraint(item: topView, attribute: .left, relatedBy: .equal,
                                         toItem: holderView, attribute: .left, multiplier: 1.0, constant: padding)
        let pinRight = NSLayoutConstraint(item: topView, attribute: .right, relatedBy: .equal,
                                          toItem: holderView, attribute: .right, multiplier: 1.0, constant: padding)
        holderView.addConstraints([pinTop, pinBottom, pinLeft, pinRight])
    }
}

extension FlutterMapboxNavigationView : UIGestureRecognizerDelegate {

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = navigationMapView.mapView.mapboxMap.coordinate(for: gesture.location(in: navigationMapView.mapView))
        requestRoute(destination: location)
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {return}
        let location = navigationMapView.mapView.mapboxMap.coordinate(for: gesture.location(in: navigationMapView.mapView))
        let waypoint: [String: Any] = [
            "latitude" : location.latitude,
            "longitude" : location.longitude,
        ]
        guard JSONSerialization.isValidJSONObject(waypoint),
              let encodedData = try? JSONSerialization.data(withJSONObject: waypoint),
              let jsonString = String(data: encodedData, encoding: .utf8),
              !jsonString.isEmpty else { return }

        sendEvent(eventType: .on_map_tap, data: jsonString)
    }

    func requestRoute(destination: CLLocationCoordinate2D) {
        isEmbeddedNavigation = true
        sendEvent(eventType: .route_building)

        guard let userLocation = navigationMapView.mapView.location.latestLocation else { return }
        let location = CLLocation(latitude: userLocation.coordinate.latitude,
                                  longitude: userLocation.coordinate.longitude)
        let userWaypoint = Waypoint(location: location, name: "Current Location")
        let destinationWaypoint = Waypoint(coordinate: destination)

        let options = NavigationRouteOptions(waypoints: [userWaypoint, destinationWaypoint])

        let request = mapboxNavigation.routingProvider().calculateRoutes(options: options)
        Task { [weak self] in
            guard let self = self else { return }
            let result = await request.result
            await MainActor.run {
                switch result {
                case .failure:
                    self.sendEvent(eventType: .route_build_failed)
                case .success(let navigationRoutes):
                    self._routes = navigationRoutes
                    self._options = options
                    self.sendEvent(eventType: .route_built, data: self.encodeRouteResponse(routes: navigationRoutes))
                    self.navigationMapView?.showcase(navigationRoutes)
                }
            }
        }
    }
}
