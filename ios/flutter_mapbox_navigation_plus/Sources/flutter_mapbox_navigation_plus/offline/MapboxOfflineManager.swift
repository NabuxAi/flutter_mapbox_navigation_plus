import Foundation
import CoreLocation
import MapboxMaps
import MapboxNavigationCore

/// Full offline support (maps + routing) for the iOS v3 implementation.
///
/// Mirrors the Android `MapboxOfflineManager`: a region is selected as an
/// arbitrary polygon and a single shared `TileStore` (the one created by the
/// Navigation SDK) is loaded with both the map tileset descriptor and the
/// navigation tileset descriptor, so one download serves the renderer and
/// routing. Progress/completion/errors are reported through the same
/// `offline_region_*` events as Android.
///
/// All Mapbox offline API usage is intentionally confined to this file.
final class MapboxOfflineManager {

    static let shared = MapboxOfflineManager()

    /// Set by the plugin so events reach the active Flutter event sink.
    /// Parameters: event name and a JSON-object payload.
    var onEvent: ((String, [String: Any]) -> Void)?

    private let offlineManager = OfflineManager()

    /// The tile store created and owned by the Navigation SDK. Both the map
    /// renderer and the routing engine read from it. Uses the *current* provider
    /// so an in-flight (possibly simulated) navigation session is never rebuilt.
    private var tileStore: TileStore {
        NavigationProviderHolder.shared.current
            .coreConfig.tilestoreConfig.navigatorLocation.tileStore
    }

    private init() {}

    /// Eagerly create the shared provider/tile store so downloaded regions are
    /// available to the first map and to routing.
    func initialize() {
        _ = tileStore
    }

    /// Download a region (map + routing tiles) covering the supplied polygon.
    ///
    /// - Parameter coordinates: outer ring as `[longitude, latitude]` pairs.
    func downloadRegion(
        regionId: String,
        coordinates: [[Double]],
        minZoom: Int,
        maxZoom: Int,
        styleUrl: String?
    ) {
        guard coordinates.count >= 3 else {
            emit("offline_region_error", ["id": regionId, "message": "A polygon needs at least 3 points"])
            return
        }

        let styleURI: StyleURI
        if let styleUrl = styleUrl, !styleUrl.isEmpty, let uri = StyleURI(rawValue: styleUrl) {
            styleURI = uri
        } else {
            styleURI = .standard
        }

        let ring = coordinates.map {
            CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
        }
        let geometry = Polygon([ring]).geometry

        let zoomRange = UInt8(max(0, minZoom))...UInt8(max(minZoom, maxZoom))
        let mapsDescriptor = offlineManager.createTilesetDescriptor(
            for: TilesetDescriptorOptions(styleURI: styleURI, zoomRange: zoomRange)
        )
        // Routing tiles for the same area so directions work offline too.
        let navDescriptor = NavigationProviderHolder.shared
            .current
            .getLatestNavigationTilesetDescriptor()

        // Style pack lets the map render fully offline (fonts, sprites, sources).
        if let stylePackOptions = StylePackLoadOptions(
            glyphsRasterizationMode: .ideographsRasterizedLocally,
            metadata: nil
        ) {
            offlineManager.loadStylePack(for: styleURI, loadOptions: stylePackOptions) { _ in }
        }

        let loadOptions = TileRegionLoadOptions(
            geometry: geometry,
            descriptors: [mapsDescriptor, navDescriptor],
            acceptExpired: true,
            networkRestriction: .none
        )

        guard let loadOptions = loadOptions else {
            emit("offline_region_error", ["id": regionId, "message": "Could not build tile region load options"])
            return
        }

        _ = tileStore.loadTileRegion(
            forId: regionId,
            loadOptions: loadOptions,
            progress: { [weak self] progress in
                let required = progress.requiredResourceCount
                let pct = required > 0
                    ? Double(progress.completedResourceCount) / Double(required) * 100.0
                    : 0.0
                self?.emit(
                    "offline_region_progress",
                    [
                        "id": regionId,
                        "progress": pct,
                        "completedResourceCount": progress.completedResourceCount,
                        "requiredResourceCount": required
                    ]
                )
            },
            completion: { [weak self] result in
                switch result {
                case .success:
                    self?.emit("offline_region_complete", ["id": regionId])
                case .failure(let error):
                    self?.emit("offline_region_error", ["id": regionId, "message": error.localizedDescription])
                }
            }
        )
    }

    /// Delete a previously downloaded region.
    func removeRegion(regionId: String) {
        tileStore.removeTileRegion(forId: regionId)
        emit("offline_region_removed", ["id": regionId])
    }

    /// Return the ids of all downloaded regions to the Flutter caller.
    func listRegions(result: @escaping ([String]) -> Void) {
        tileStore.allTileRegions { regionsResult in
            let ids: [String]
            switch regionsResult {
            case .success(let regions):
                ids = regions.map { $0.id }
            case .failure:
                ids = []
            }
            // TileStore callbacks may arrive on a worker thread; channel results
            // must be delivered on the platform (main) thread.
            DispatchQueue.main.async { result(ids) }
        }
    }

    private func emit(_ eventType: String, _ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(eventType, data)
        }
    }
}
