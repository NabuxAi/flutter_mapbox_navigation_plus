# iOS Manual Test Checklist (Mapbox Navigation SDK v3)

CI compiles the iOS implementation (`ios-build` job), but it does **not** exercise
runtime behaviour. This checklist verifies the v3 iOS implementation on a real
device. Run on a **physical device** (the simulator has no real GPS); for
turn-by-turn without driving, use `simulateRoute: true`.

Each item lists the action, the expected result, and the event(s) to observe via
`MapBoxNavigation.instance.registerRouteEventListener(...)`.

## 0. Setup (once)

- [ ] `MBXAccessToken` (public token) set in `Info.plist`
- [ ] `~/.netrc` has the `DOWNLOADS:READ` token (so SPM can fetch the SDK)
- [ ] Flutter SPM enabled: `flutter config --enable-swift-package-manager`
- [ ] App deployment target is **iOS 14+**
- [ ] Location permission granted; Background Modes include `audio` and `location`
- [ ] A route-event listener prints every event to the console

## 1. Full-screen navigation — `MapBoxNavigation.instance.startNavigation`

Use `simulateRoute: true` and two valid waypoints.

- [ ] Event order: `route_building` → `route_built` → `navigation_running`
- [ ] `progress_change` stream arrives with sensible `distanceRemaining`,
      `durationRemaining`, `currentSpeed` (≥ 0)
- [ ] Voice guidance is audible
- [ ] Native v3 maneuver banner + trip-progress (ETA) bar are shown
- [ ] Arriving at the destination → `on_arrival`, and `arrived == true` in progress
- [ ] `finishNavigation()` closes the screen → `navigation_finished`
- [ ] Cancelling with the native button → `navigation_cancelled`
- [ ] Multi-stop (3+ waypoints) → `on_arrival` fires at each stop; final arrival ends the trip
- [ ] `language: "fa"` (or `"ar"`) → instruction text is correct and the event
      stream does not stop (UTF-8 regression check)

## 2. Embedded navigation view — `MapBoxNavigationView` + controller

- [ ] Map renders (not black) and the location puck appears
- [ ] `controller.buildRoute(...)` → route line + origin/destination markers
      (showcase) and a `route_built` event
- [ ] `controller.startNavigation()` → embedded turn-by-turn starts
- [ ] `isV3` returns **true** (Flutter must not draw a second HUD)
- [ ] `recenter()` returns the camera to follow the user
- [ ] `toggleVoiceInstructions()` mutes/unmutes voice
- [ ] `clearRoute()` → route cleared + `navigation_cancelled`
- [ ] `finishNavigation()` removes the embedded turn-by-turn view

## 3. Free drive

- [ ] Embedded `startFreeDrive(...)` → camera follows the user with no route
- [ ] Full-screen `startFreeDrive(...)` → a following map is presented
      (see "Known limitations": no built-in close button)

## 4. Live values

- [ ] `getDistanceRemaining()` / `getDurationRemaining()` return numbers during navigation

## 5. Offline maps & routing 🔌

- [ ] `downloadOfflineRegion(OfflineRegion.fromBounds(...))` → `offline_region_progress`
      stream with an increasing percentage
- [ ] Download finishes → `offline_region_complete`
- [ ] The polygon form (`OfflineRegion(coordinates: …)`) behaves the same
- [ ] `getOfflineRegions()` returns the region id
- [ ] **Airplane mode ON**, inside the region: the map renders and
      `buildRoute` / `startNavigation` computes a route with no network ✈️
- [ ] `removeOfflineRegion(id)` → `offline_region_removed` and the id leaves the list

## 6. Error / edge cases

- [ ] Invalid coordinates / no route → `route_build_failed`
- [ ] Backgrounding the app mid-navigation keeps voice + location updates alive

---

## Notes / things to watch

1. **Full-screen free drive close button.** `FreeDriveViewController` now shows a
   close button (top-left) that ends the passive session and dismisses the screen.
2. **`addWayPoints` during an active full-screen trip** now updates the running
   trip in place via `tripSession().startActiveGuidance(with:startLegIndex:)`
   instead of presenting a second `NavigationViewController`. Verify the route
   updates without a flicker.
3. **Custom night style.** When `mapStyleUrlNight` is set and the device is in
   dark mode, it is applied to the full-screen, embedded and free-drive maps; the
   day style is used otherwise. (During active guidance the SDK may still manage
   day/night transitions.)
4. **`on_arrival` delegate — verify on device.** `Waypoint` is aliased to
   `MapboxDirections.Waypoint`; confirm `on_arrival` fires (the one delegate whose
   type match the compiler cannot fully guarantee). Final arrival is also exposed
   via the `arrived` flag on `progress_change`, so the end-of-trip case has a
   fallback even if the delegate does not fire.
