// CarPlay scene delegate template for flutter_mapbox_navigation_plus.
//
// Copy this file into your Flutter app's `ios/Runner/` folder and register it in
// Info.plist (see docs/CARPLAY_ANDROID_AUTO.md). It is a TEMPLATE and is not
// compiled as part of the plugin — it must live in the host app so it can use
// the CarPlay entitlement and scene manifest, which only the app can declare.

import CarPlay
import MapboxNavigationCore
import MapboxNavigationUIKit
import flutter_mapbox_navigation_plus

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var carPlayManager: CarPlayManager?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        // Reuse the SAME provider the Flutter plugin drives, so a route built
        // from Flutter, the active trip, voice guidance and downloaded offline
        // tiles are all immediately available on the car screen.
        let provider = NavigationProviderHolder.shared.current

        let manager = CarPlayManager(navigationProvider: provider)
        manager.delegate = self
        self.carPlayManager = manager

        manager.templateApplicationScene(
            templateApplicationScene,
            didConnect: interfaceController,
            to: window
        )
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        carPlayManager?.templateApplicationScene(
            templateApplicationScene,
            didDisconnectInterfaceController: interfaceController,
            from: window
        )
        carPlayManager = nil
    }
}

// Implement any optional hooks (search, custom trip preview, styling) here.
extension CarPlaySceneDelegate: CarPlayManagerDelegate {}
