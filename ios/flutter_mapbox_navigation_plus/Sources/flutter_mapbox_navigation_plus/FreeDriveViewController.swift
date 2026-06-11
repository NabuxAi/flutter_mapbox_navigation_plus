import UIKit
import Combine
import MapboxMaps
import MapboxNavigationCore
import MapboxNavigationUIKit

/// Lightweight full-screen free-drive (passive navigation) screen for v3.
///
/// Shows a `NavigationMapView` following the user's location with predictive
/// caching, without an active route. A close button lets the user dismiss it.
class FreeDriveViewController: UIViewController {

    private let provider: MapboxNavigationProvider
    private let mapStyleUrlDay: String?
    private let mapStyleUrlNight: String?
    private let zoom: Double
    private var navigationMapView: NavigationMapView!

    init(provider: MapboxNavigationProvider, mapStyleUrlDay: String?, mapStyleUrlNight: String?, zoom: Double) {
        self.provider = provider
        self.mapStyleUrlDay = mapStyleUrlDay
        self.mapStyleUrlNight = mapStyleUrlNight
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

        // Honor the night style when the device is in dark mode.
        let styleUrl = (traitCollection.userInterfaceStyle == .dark && !(mapStyleUrlNight ?? "").isEmpty)
            ? mapStyleUrlNight
            : mapStyleUrlDay
        if let styleUrl = styleUrl, let uri = StyleURI(rawValue: styleUrl) {
            navigationMapView.mapView.mapboxMap.mapStyle = MapStyle(uri: uri)
        }
        view.addSubview(navigationMapView)

        addCloseButton()

        // Begin passive (free-drive) location updates so the puck follows.
        nav.tripSession().startFreeDrive()
    }

    private func addCloseButton() {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        closeButton.layer.cornerRadius = 22
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func closeTapped() {
        provider.mapboxNavigation.tripSession().setToIdle()
        dismiss(animated: true)
    }
}
