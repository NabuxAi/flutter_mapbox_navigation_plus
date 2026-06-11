# Mapbox Navigation SDK v3 Migration

The Android implementation now builds Mapbox Navigation SDK v3 (Maps SDK v11) by
default. There is no longer a `BIKO_MAPBOX_NAV_V3` build flag — `android/build.gradle`
always compiles the `src/v3` source set.

The legacy v2 implementation (Mapbox Navigation SDK 2.16.0) is kept in the repo under
`src/main` for reference but is **not compiled**:

- `com.mapbox.navigation:copilot:2.16.0`
- `com.mapbox.navigation:ui-app:2.16.0`
- `com.mapbox.navigation:ui-dropin:2.16.0`
- `com.mapbox.navigation.dropin.NavigationView`

Navigation SDK v3 moves to Maps SDK v11 and removes the v2 Drop-in UI. The v3 implementation replaces `NavigationView` with a native `MapView` plus Navigation SDK observers, route line rendering, camera handling, voice/banner events, arrival events, and Flutter overlay controls.

Do not add `mapbox_maps_flutter` beside this v2 package in the app. The app will fail Android duplicate-class checks because v2 brings Maps SDK v10 and `mapbox_maps_flutter` brings Maps SDK v11.

## iOS Migration

The iOS implementation now builds against the **Mapbox Navigation SDK v3** (Maps
SDK v11). v3 is distributed **only** through Swift Package Manager — there is no
CocoaPods release — so the integration model changed:

- The plugin ships `ios/flutter_mapbox_navigation_plus/Package.swift`, which
  depends on `mapbox-navigation-ios` (`MapboxNavigationCore` + `MapboxNavigationUIKit`)
  and `mapbox-maps-ios` (`MapboxMaps`). Source files moved to the SPM layout under
  `ios/flutter_mapbox_navigation_plus/Sources/flutter_mapbox_navigation_plus/`.
- The `.podspec` is kept for Flutter tooling but no longer declares the Mapbox
  dependency (CocoaPods cannot resolve v3). **Host apps must enable Flutter's
  Swift Package Manager support and target iOS 14+.**

What changed in the native code:

- Routing moved from `Directions.shared.calculate` (completion handler) to the v3
  async `MapboxNavigationProvider.routingProvider().calculateRoutes(options:)`,
  returning `NavigationRoutes` instead of `RouteResponse`.
- A single shared `MapboxNavigationProvider` (`NavigationProviderHolder`) backs
  routing, active guidance, the embedded `NavigationMapView` and the offline tile
  store, mirroring how the Android v3 implementation centralizes the SDK.
- Full-screen turn-by-turn uses the v3 `NavigationViewController(navigationRoutes:
  navigationOptions:)`; progress, arrival and dismissal flow through
  `NavigationViewControllerDelegate`. Route simulation maps to
  `CoreConfig(locationSource: .simulation(...))`.
- The embedded platform view renders route previews with `NavigationMapView`
  (location + route-progress Combine publishers) and `showcase(_:)`, then embeds a
  `NavigationViewController` for active guidance. `isV3` now returns `true` on iOS.
- The legacy v2-only files (`RouteOptionsViewController`, the `DayStyle`/`NightStyle`
  subclasses and the stubbed `downloadOfflineRoute`) were removed.

### Offline maps & routing (iOS)

`MapboxOfflineManager` mirrors the Android offline manager: it loads the shared
`TileStore` (created by the Navigation SDK) with both the **map** tileset
descriptor (`OfflineManager.createTilesetDescriptor`) and the **navigation**
tileset descriptor (`MapboxNavigationProvider.getLatestNavigationTilesetDescriptor()`),
plus a style pack, so one polygon download serves the renderer and routing.
Progress/completion/errors are emitted as the same `offline_region_*` events used
on Android, keeping the Dart API identical across platforms.

### Verifying the build

There is no iOS toolchain in CI by default, so a `macos` job (`ios-build` in
`.github/workflows/ci.yml`) compiles the example app through SPM. It requires the
`MAPBOX_DOWNLOADS_TOKEN` secret (a token with the `downloads:read` scope), which is
written to `~/.netrc` so SPM can fetch the Mapbox binaries.
