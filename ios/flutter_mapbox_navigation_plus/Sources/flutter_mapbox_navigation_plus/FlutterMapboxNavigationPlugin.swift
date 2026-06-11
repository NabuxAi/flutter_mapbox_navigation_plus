import Flutter
import UIKit

public class FlutterMapboxNavigationPlugin: NavigationFactory, FlutterPlugin {
    @MainActor
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_mapbox_navigation", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_mapbox_navigation/events", binaryMessenger: registrar.messenger())
        let instance = FlutterMapboxNavigationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        eventChannel.setStreamHandler(instance)

        // Route offline_region_* events (worker-thread callbacks) to this
        // plugin's Flutter event sink as object-payload events. The callback can
        // arrive off the main thread, so hop to the main actor before touching
        // the (main-actor-isolated) plugin instance.
        MapboxOfflineManager.shared.onEvent = { [weak instance] eventType, data in
            Task { @MainActor in
                instance?.sendObjectEvent(eventType: eventType, data: data)
            }
        }

        let viewFactory = FlutterMapboxNavigationViewFactory(messenger: registrar.messenger())
        registrar.register(viewFactory, withId: "FlutterMapboxNavigationView")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

        let arguments = call.arguments as? NSDictionary

        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getDistanceRemaining":
            result(_distanceRemaining)
        case "getDurationRemaining":
            result(_durationRemaining)
        case "startFreeDrive":
            startFreeDrive(arguments: arguments, result: result)
        case "startNavigation":
            startNavigation(arguments: arguments, result: result)
        case "addWayPoints":
            addWayPoints(arguments: arguments, result: result)
        case "finishNavigation":
            endNavigation(result: result)
        case "enableOfflineRouting":
            // v3 routes offline automatically when tiles for the area exist.
            // Make sure the shared tile store is ready.
            MapboxOfflineManager.shared.initialize()
            result(true)
        case "downloadOfflineRegion":
            downloadOfflineRegion(arguments: arguments, result: result)
        case "removeOfflineRegion":
            removeOfflineRegion(arguments: arguments, result: result)
        case "getOfflineRegions":
            MapboxOfflineManager.shared.listRegions { ids in
                result(ids)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func downloadOfflineRegion(arguments: NSDictionary?, result: @escaping FlutterResult) {
        MapboxOfflineManager.shared.initialize()
        let id = arguments?["id"] as? String ?? "default-region"
        let minZoom = (arguments?["minZoom"] as? NSNumber)?.intValue ?? 0
        let maxZoom = (arguments?["maxZoom"] as? NSNumber)?.intValue ?? 16
        let styleUrl = arguments?["styleUrl"] as? String
        // Channel codec delivers the [lng, lat] pairs as nested NSNumber arrays.
        let rawCoordinates = (arguments?["coordinates"] as? [[Any]]) ?? []
        let coordinates: [[Double]] = rawCoordinates.map { pair in
            pair.compactMap { ($0 as? NSNumber)?.doubleValue }
        }
        MapboxOfflineManager.shared.downloadRegion(
            regionId: id,
            coordinates: coordinates,
            minZoom: minZoom,
            maxZoom: maxZoom,
            styleUrl: styleUrl
        )
        result(true)
    }

    private func removeOfflineRegion(arguments: NSDictionary?, result: @escaping FlutterResult) {
        guard let id = arguments?["id"] as? String else {
            result(FlutterError(code: "NO_ID", message: "An offline region id is required.", details: nil))
            return
        }
        MapboxOfflineManager.shared.initialize()
        MapboxOfflineManager.shared.removeRegion(regionId: id)
        result(true)
    }
}
