import Foundation
import MapboxNavigationCore

/// Owns the single `MapboxNavigationProvider` shared by the whole plugin.
///
/// Navigation SDK v3 funnels everything (routing, active guidance, the tile
/// store used for offline data and the predictive cache) through one provider,
/// so a single shared instance keeps the full-screen flow, the embedded map and
/// the offline manager consistent.
///
/// The location source is fixed when a provider is created, so the provider is
/// rebuilt when the caller toggles route simulation. The on-disk tile store is
/// keyed by location and therefore survives a provider rebuild, so downloaded
/// offline regions are not lost.
final class NavigationProviderHolder {

    static let shared = NavigationProviderHolder()

    /// The currently active provider. Read this when you must not change the
    /// simulation mode (e.g. the offline manager), so an in-flight navigation
    /// session is never torn down.
    private(set) var current: MapboxNavigationProvider
    private var simulating = false

    private init() {
        current = MapboxNavigationProvider(coreConfig: CoreConfig(locationSource: .live))
    }

    /// Returns the shared provider, rebuilding it only if the simulation mode
    /// changed since the last call.
    @discardableResult
    func provider(simulating: Bool) -> MapboxNavigationProvider {
        if simulating != self.simulating {
            self.simulating = simulating
            current = MapboxNavigationProvider(
                coreConfig: CoreConfig(
                    locationSource: simulating ? .simulation(initialLocation: nil) : .live
                )
            )
        }
        return current
    }

    var mapboxNavigation: MapboxNavigation { current.mapboxNavigation }
}
