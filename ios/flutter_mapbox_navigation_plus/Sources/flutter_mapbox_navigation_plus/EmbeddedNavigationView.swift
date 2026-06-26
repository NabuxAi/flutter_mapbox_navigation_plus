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
    /// Forwards free-drive/idle location updates to Dart as `location_change`.
    var locationCancellable: AnyCancellable?

    // Dart-driven map markers, keyed by the caller-provided id.
    var circleAnnotationManager: CircleAnnotationManager?
    var pointAnnotationManager: PointAnnotationManager?
    var polylineAnnotationManager: PolylineAnnotationManager?
    var polygonAnnotationManager: PolygonAnnotationManager?
    var markerCircles: [String: CircleAnnotation] = [:]
    var markerLabels: [String: PointAnnotation] = [:]
    var userPolylines: [String: PolylineAnnotation] = [:]
    var circlePolygons: [String: PolygonAnnotation] = [:]
    var circleStrokes: [String: PolylineAnnotation] = [:]

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
            case "overview":
                strongSelf.navigationMapView?.navigationCamera.update(cameraState: .overview)
                result(true)
            case "moveCamera":
                strongSelf.moveCamera(arguments: arguments, result: result)
            case "getCurrentLocation":
                let coord = strongSelf.navigationMapView?.mapView.location.latestLocation?.coordinate
                    ?? strongSelf._lastKnownLocation?.coordinate
                if let coord = coord {
                    result([
                        "latitude": coord.latitude,
                        "longitude": coord.longitude,
                        "bearing": strongSelf._lastKnownLocation?.course ?? 0,
                        "speed": max(strongSelf._lastKnownLocation?.speed ?? 0, 0),
                    ])
                } else {
                    result(nil)
                }
            case "getCameraPosition":
                let c = strongSelf.navigationMapView.mapView.mapboxMap.cameraState
                result([
                    "latitude": c.center.latitude,
                    "longitude": c.center.longitude,
                    "zoom": c.zoom,
                    "bearing": c.bearing,
                    "tilt": c.pitch,
                ])
            case "fitBounds":
                strongSelf.fitBounds(arguments: arguments, result: result)
            case "toggleVoiceInstructions":
                let requested = call.arguments as? Bool
                result(strongSelf.toggleEmbeddedVoiceInstructions(requested))
            case "addMarkers":
                if let markers = arguments?["markers"] as? [Any] {
                    strongSelf.addMarkers(markers)
                    result(true)
                } else {
                    result(false)
                }
            case "removeMarker":
                if let id = arguments?["id"] as? String {
                    strongSelf.removeMarker(id: id)
                }
                result(true)
            case "clearMarkers":
                strongSelf.clearMarkers()
                result(true)
            case "addPolylines":
                if let list = arguments?["polylines"] as? [Any] {
                    strongSelf.addPolylines(list)
                    result(true)
                } else {
                    result(false)
                }
            case "removePolyline":
                if let id = arguments?["id"] as? String { strongSelf.removePolyline(id: id) }
                result(true)
            case "clearPolylines":
                strongSelf.clearPolylines()
                result(true)
            case "addCircles":
                if let list = arguments?["circles"] as? [Any] {
                    strongSelf.addCircles(list)
                    result(true)
                } else {
                    result(false)
                }
            case "removeCircle":
                if let id = arguments?["id"] as? String { strongSelf.removeCircle(id: id) }
                result(true)
            case "clearCircles":
                strongSelf.clearCircles()
                result(true)
            case "addWayPoints":
                strongSelf.addEmbeddedWayPoints(arguments: arguments, result: result)
            case "selectAlternativeRoute":
                let index = (arguments?["index"] as? Int) ?? 0
                strongSelf.selectAlternativeRoute(index: index, result: result)
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

        if let styleUrl = resolvedMapStyleUrl(for: navigationMapView.traitCollection),
           let uri = StyleURI(rawValue: styleUrl) {
            navigationMapView.mapView.mapboxMap.mapStyle = MapStyle(uri: uri)
        }

        locationManager.requestWhenInUseAuthorization()
        // Begin passive location updates so the puck follows the user.
        nav.tripSession().startFreeDrive()

        // Stream real GPS speed/position to Dart even when not navigating
        // (free drive / idle). During active navigation the NavigationViewController
        // delegate already emits location_change, so skip it here to avoid
        // duplicate events.
        locationCancellable = nav.navigation().locationMatching
            .sink { [weak self] state in
                guard let self = self, self._navigationViewController == nil else { return }
                let loc = state.enhancedLocation
                self._lastKnownLocation = loc
                self.sendObjectEvent(eventType: "location_change", data: [
                    "latitude": loc.coordinate.latitude,
                    "longitude": loc.coordinate.longitude,
                    "bearing": loc.course,
                    "speed": max(loc.speed, 0),
                ])
            }

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
                    self.sendAlternatives(routes: navigationRoutes)
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

        // Apply the app's custom Mapbox style to the EMBEDDED turn-by-turn map
        // too (the full-screen path in NavigationFactory already does this). Without
        // it, iOS embedded nav fell back to the SDK's default style while Android
        // used mapStyleUrlDay — making the two platforms look different.
        applyCustomStyleIfNeeded(to: navigationViewController)

        // Any root view controller can host the child. Resolve it via the active
        // window scene so it works under the UIScene lifecycle (FlutterSceneDelegate),
        // where UIApplication.shared.delegate?.window is nil.
        guard let hostViewController = UIApplication.shared.activeRootViewController else {
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

    /// Append one or more intermediate stops to the route currently shown or
    /// navigated and recompute it. If a trip is active, guidance continues along
    /// the updated route.
    func addEmbeddedWayPoints(arguments: NSDictionary?, result: @escaping FlutterResult) {
        guard let locations = getLocationsFromFlutterArgument(arguments: arguments) else {
            result(false)
            return
        }
        for loc in locations {
            var waypoint = Waypoint(
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude!, longitude: loc.longitude!),
                name: loc.name
            )
            waypoint.separatesLegs = !loc.isSilent
            _wayPoints.append(waypoint)
        }

        setNavigationOptions(wayPoints: _wayPoints)
        guard let options = _options else {
            result(false)
            return
        }

        let request = mapboxNavigation.routingProvider().calculateRoutes(options: options)
        Task { [weak self] in
            guard let self = self else { return }
            let routeResult = await request.result
            await MainActor.run {
                switch routeResult {
                case .failure:
                    self.sendEvent(eventType: .route_build_failed)
                    result(false)
                case .success(let navigationRoutes):
                    self._routes = navigationRoutes
                    self.sendEvent(eventType: .route_built, data: self.encodeRouteResponse(routes: navigationRoutes))
                    self.sendAlternatives(routes: navigationRoutes)
                    self.navigationMapView?.showcase(navigationRoutes)
                    // Keep an active trip going along the new route.
                    if self._navigationViewController != nil {
                        self.mapboxNavigation.tripSession().startActiveGuidance(
                            with: navigationRoutes,
                            startLegIndex: 0
                        )
                    }
                    result(true)
                }
            }
        }
    }

    /// Promote the alternative route at `index` (0 = current main route) to the
    /// primary route, using the v3 `NavigationRoutes.selecting(alternativeRoute:)`
    /// API. Re-showcases and, if navigating, restarts guidance on the new route.
    func selectAlternativeRoute(index: Int, result: @escaping FlutterResult) {
        guard let routes = _routes else {
            result(false)
            return
        }
        if index <= 0 {
            // The main route is already primary; just re-frame it.
            navigationMapView?.showcase(routes)
            result(true)
            return
        }
        let alternativeIndex = index - 1
        guard alternativeIndex < routes.alternativeRoutes.count else {
            result(false)
            return
        }
        let alternative = routes.alternativeRoutes[alternativeIndex]
        Task { [weak self] in
            guard let self = self else { return }
            let selected = await routes.selecting(alternativeRoute: alternative)
            await MainActor.run {
                guard let selected = selected else {
                    result(false)
                    return
                }
                self._routes = selected
                self.navigationMapView?.showcase(selected)
                self.sendAlternatives(routes: selected)
                if self._navigationViewController != nil {
                    self.mapboxNavigation.tripSession().startActiveGuidance(
                        with: selected,
                        startLegIndex: 0
                    )
                }
                result(true)
            }
        }
    }

    func moveCamera(arguments: NSDictionary?, result: @escaping FlutterResult) {
        guard let lat = arguments?["latitude"] as? Double,
              let lng = arguments?["longitude"] as? Double else {
            result(false)
            return
        }
        // Detach the navigation camera so it stops driving the view.
        navigationMapView?.navigationCamera.update(cameraState: .idle)
        var camera = CameraOptions(center: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        if let zoom = arguments?["zoom"] as? Double { camera.zoom = zoom }
        if let bearing = arguments?["bearing"] as? Double { camera.bearing = bearing }
        if let tilt = arguments?["tilt"] as? Double { camera.pitch = tilt }

        let mapView = navigationMapView.mapView
        if arguments?["animate"] as? Bool ?? true {
            let ms = (arguments?["durationMs"] as? Int) ?? 1000
            mapView.camera.fly(to: camera, duration: Double(ms) / 1000.0)
        } else {
            mapView.mapboxMap.setCamera(to: camera)
        }
        result(true)
    }

    func fitBounds(arguments: NSDictionary?, result: @escaping FlutterResult) {
        guard let swLat = arguments?["southwestLat"] as? Double,
              let swLng = arguments?["southwestLng"] as? Double,
              let neLat = arguments?["northeastLat"] as? Double,
              let neLng = arguments?["northeastLng"] as? Double else {
            result(false)
            return
        }
        navigationMapView?.navigationCamera.update(cameraState: .idle)
        let pad = arguments?["padding"] as? Double ?? 40
        let coordinates = [
            CLLocationCoordinate2D(latitude: neLat, longitude: neLng),
            CLLocationCoordinate2D(latitude: swLat, longitude: swLng),
        ]
        let mapView = navigationMapView.mapView
        let camera = mapView.mapboxMap.camera(
            for: coordinates,
            padding: UIEdgeInsets(top: pad, left: pad, bottom: pad, right: pad),
            bearing: nil,
            pitch: nil
        )
        if arguments?["animate"] as? Bool ?? true {
            mapView.camera.fly(to: camera, duration: 1.0)
        } else {
            mapView.mapboxMap.setCamera(to: camera)
        }
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

// MARK: - Dart-driven map markers

extension FlutterMapboxNavigationView {

    func ensureAnnotationManagers() {
        if polygonAnnotationManager == nil {
            polygonAnnotationManager = navigationMapView.mapView.annotations.makePolygonAnnotationManager()
        }
        if circleAnnotationManager == nil {
            circleAnnotationManager = navigationMapView.mapView.annotations.makeCircleAnnotationManager()
        }
        if polylineAnnotationManager == nil {
            polylineAnnotationManager = navigationMapView.mapView.annotations.makePolylineAnnotationManager()
        }
        // Point manager last so labels/icons draw above the shapes.
        if pointAnnotationManager == nil {
            pointAnnotationManager = navigationMapView.mapView.annotations.makePointAnnotationManager()
        }
    }

    func addMarkers(_ markers: [Any]) {
        ensureAnnotationManagers()
        for raw in markers {
            guard let marker = raw as? [String: Any],
                  let id = marker["id"] as? String,
                  let lat = marker["latitude"] as? Double,
                  let lng = marker["longitude"] as? Double else { continue }
            let colorHex = marker["color"] as? String ?? "#FF3B30"
            let radius = marker["radius"] as? Double ?? 8.0
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let label = marker["label"] as? String

            // Remove any existing marker/icon under this id first.
            markerCircles.removeValue(forKey: id)
            markerLabels.removeValue(forKey: id)

            if let image = decodeMarkerImage(
                marker["imageBase64"] as? String,
                width: marker["imageWidth"] as? Double,
                height: marker["imageHeight"] as? Double
            ) {
                var point = PointAnnotation(coordinate: coordinate)
                point.image = .init(image: image, name: "marker-\(id)")
                if let label = label, !label.isEmpty {
                    point.textField = label
                    point.textOffset = [0, 1.4]
                    point.textColor = StyleColor(UIColor.black)
                    point.textHaloColor = StyleColor(UIColor.white)
                    point.textHaloWidth = 1.0
                }
                markerLabels[id] = point
            } else {
                var circle = CircleAnnotation(centerCoordinate: coordinate)
                circle.circleRadius = radius
                circle.circleColor = StyleColor(UIColor(hexString: colorHex))
                circle.circleStrokeColor = StyleColor(UIColor.white)
                circle.circleStrokeWidth = 2.0
                markerCircles[id] = circle

                if let label = label, !label.isEmpty {
                    var point = PointAnnotation(coordinate: coordinate)
                    point.textField = label
                    point.textOffset = [0, -1.6]
                    point.textColor = StyleColor(UIColor.black)
                    point.textHaloColor = StyleColor(UIColor.white)
                    point.textHaloWidth = 1.0
                    markerLabels[id] = point
                }
            }
        }
        syncAnnotations()
    }

    private func decodeMarkerImage(_ base64: String?, width: Double?, height: Double?) -> UIImage? {
        guard let base64 = base64, !base64.isEmpty,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        guard let width = width, let height = height else { return image }
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    func removeMarker(id: String) {
        markerCircles.removeValue(forKey: id)
        markerLabels.removeValue(forKey: id)
        syncAnnotations()
    }

    func clearMarkers() {
        markerCircles.removeAll()
        markerLabels.removeAll()
        syncAnnotations()
    }

    func addPolylines(_ list: [Any]) {
        ensureAnnotationManagers()
        for raw in list {
            guard let item = raw as? [String: Any],
                  let id = item["id"] as? String,
                  let pts = item["points"] as? [Any] else { continue }
            let coords = pts.compactMap { p -> CLLocationCoordinate2D? in
                guard let pair = p as? [Any], pair.count >= 2,
                      let plat = pair[0] as? Double, let plng = pair[1] as? Double else { return nil }
                return CLLocationCoordinate2D(latitude: plat, longitude: plng)
            }
            if coords.count < 2 { continue }
            let colorHex = item["color"] as? String ?? "#1A73E8"
            let width = item["width"] as? Double ?? 5.0
            var line = PolylineAnnotation(lineCoordinates: coords)
            line.lineColor = StyleColor(UIColor(hexString: colorHex))
            line.lineWidth = width
            userPolylines[id] = line
        }
        syncAnnotations()
    }

    func removePolyline(id: String) {
        userPolylines.removeValue(forKey: id)
        syncAnnotations()
    }

    func clearPolylines() {
        userPolylines.removeAll()
        syncAnnotations()
    }

    func addCircles(_ list: [Any]) {
        ensureAnnotationManagers()
        for raw in list {
            guard let item = raw as? [String: Any],
                  let id = item["id"] as? String,
                  let lat = item["latitude"] as? Double,
                  let lng = item["longitude"] as? Double,
                  let radius = item["radiusMeters"] as? Double else { continue }
            let fillHex = item["fillColor"] as? String ?? "#331A73E8"
            let strokeHex = item["strokeColor"] as? String ?? "#1A73E8"
            let strokeWidth = item["strokeWidth"] as? Double ?? 2.0

            let ring = circleRing(latitude: lat, longitude: lng, radiusMeters: radius)
            var polygon = PolygonAnnotation(polygon: Polygon([ring]))
            let fillColor = UIColor(hexString: fillHex)
            polygon.fillColor = StyleColor(fillColor)
            var alpha: CGFloat = 0
            fillColor.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            polygon.fillOpacity = Double(alpha)
            circlePolygons[id] = polygon

            var stroke = PolylineAnnotation(lineCoordinates: ring)
            stroke.lineColor = StyleColor(UIColor(hexString: strokeHex))
            stroke.lineWidth = strokeWidth
            circleStrokes[id] = stroke
        }
        syncAnnotations()
    }

    func removeCircle(id: String) {
        circlePolygons.removeValue(forKey: id)
        circleStrokes.removeValue(forKey: id)
        syncAnnotations()
    }

    func clearCircles() {
        circlePolygons.removeAll()
        circleStrokes.removeAll()
        syncAnnotations()
    }

    /// Approximate a metric-radius circle as a 64-point geographic ring.
    private func circleRing(latitude: Double, longitude: Double, radiusMeters: Double) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let earth = 6378137.0
        let latRad = latitude * .pi / 180.0
        let steps = 64
        for i in 0...steps {
            let angle = 2.0 * Double.pi * Double(i) / Double(steps)
            let dx = radiusMeters * cos(angle)
            let dy = radiusMeters * sin(angle)
            let dLat = (dy / earth) * 180.0 / .pi
            let dLng = (dx / (earth * cos(latRad))) * 180.0 / .pi
            coords.append(CLLocationCoordinate2D(latitude: latitude + dLat, longitude: longitude + dLng))
        }
        return coords
    }

    private func syncAnnotations() {
        circleAnnotationManager?.annotations = Array(markerCircles.values)
        pointAnnotationManager?.annotations = Array(markerLabels.values)
        polylineAnnotationManager?.annotations =
            Array(userPolylines.values) + Array(circleStrokes.values)
        polygonAnnotationManager?.annotations = Array(circlePolygons.values)
    }
}

extension UIColor {
    /// Build a color from a `#RRGGBB` or `#AARRGGBB` hex string. Falls back to a
    /// red marker color when the string can't be parsed.
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch hex.count {
        case 8:
            a = (value >> 24) & 0xff
            r = (value >> 16) & 0xff
            g = (value >> 8) & 0xff
            b = value & 0xff
        case 6:
            a = 0xff
            r = (value >> 16) & 0xff
            g = (value >> 8) & 0xff
            b = value & 0xff
        default:
            a = 0xff; r = 0xff; g = 0x3b; b = 0x30
        }
        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
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
