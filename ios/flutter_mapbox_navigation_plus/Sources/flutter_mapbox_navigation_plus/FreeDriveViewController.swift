import UIKit
import Combine
import MapboxMaps
import MapboxNavigationCore
import MapboxNavigationUIKit

/// Lightweight full-screen free-drive (passive navigation) screen for v3.
///
/// Shows a `NavigationMapView` following the user's location with predictive
/// caching, without an active route.
class FreeDriveViewController: UIViewController {

    private let provider: MapboxNavigationProvider
    private let mapStyleUrlDay: String?
    private let zoom: Double
    private var navigationMapView: NavigationMapView!

    init(provider: MapboxNavigationProvider, mapStyleUrlDay: String?, zoom: Double) {
        self.provider = provider
        self.mapStyleUrlDay = mapStyleUrlDay
        self.zoom = zoom
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let nav = provider.mapboxNavigation

        navigationMapView = NavigationMapView(
            location: nav.navigation().locationMatching.map(\.enhancedLocation).eraseToAnyPublisher(),
            routeProgress: nav.navigation().routeProgress.map(\.?.routeProgress).eraseToAnyPublisher(),
            predictiveCacheManager: provider.predictiveCacheManager
        )
        navigationMapView.frame = view.bounds
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if let styleUrl = mapStyleUrlDay, let uri = StyleURI(rawValue: styleUrl) {
            navigationMapView.mapView.mapboxMap.mapStyle = MapStyle(uri: uri)
        }
        view.addSubview(navigationMapView)

        // Begin passive (free-drive) location updates so the puck follows.
        nav.tripSession().startFreeDrive()
    }
}
