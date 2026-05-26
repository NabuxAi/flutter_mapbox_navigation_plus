# Mapbox Navigation SDK v3 Migration

The current Android implementation uses Mapbox Navigation SDK 2.16.0:

- `com.mapbox.navigation:copilot:2.16.0`
- `com.mapbox.navigation:ui-app:2.16.0`
- `com.mapbox.navigation:ui-dropin:2.16.0`
- `com.mapbox.navigation.dropin.NavigationView`

Navigation SDK v3 moves to Maps SDK v11 and removes the v2 Drop-in UI. The v3 branch must replace `NavigationView` with a native `MapView` plus Navigation SDK observers, route line rendering, camera handling, voice/banner events, arrival events, and Flutter overlay controls.

Do not add `mapbox_maps_flutter` beside this v2 package in the app. The app will fail Android duplicate-class checks because v2 brings Maps SDK v10 and `mapbox_maps_flutter` brings Maps SDK v11.

## iOS Migration Status

iOS v3 migration is pending. As of now, Mapbox Navigation SDK v3 for iOS is primarily distributed via Swift Package Manager (SPM). The CocoaPods trunk currently lists `2.21.0` as the latest version. Parity enum cases have been added to the iOS implementation to support future v3 events, but the dependency upgrade will be performed once v3 is readily available via CocoaPods or the package switches to SPM.
