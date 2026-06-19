## 1.6.0
* **Camera control from Dart** on the embedded view (Android & iOS): `moveCamera` (animated or instant; center/zoom/bearing/tilt), `overview` (frame the route), `getCameraPosition`, and `fitBounds` (fit a bounding box with padding). Adds a `CameraPosition` model.

## 1.5.1
* Example app overhaul: a home menu plus a new **Custom Navigation UI** screen that builds a complete Flutter turn-by-turn UI on the embedded map (maneuver card with turn icons, ETA/distance/speed panel, alternative-route chips with selection, "add a stop", recenter and mute) — a reference for building your own branded UI from the route events.
* Docs: README highlights the new markers / route-avoidance / alternatives / mid-trip-stops / CarPlay & Android Auto features and links to the custom-UI example.

## 1.5.0
* **CarPlay & Android Auto support.** The iOS `NavigationProviderHolder` is now public so a host app's CarPlay scene delegate can build its `CarPlayManager` against the *same* navigation provider the plugin uses — phone and car share one route, guidance and offline tile store. Added a full integration guide (`docs/CARPLAY_ANDROID_AUTO.md`) with ready-to-copy templates for the iOS CarPlay scene delegate and the Android Auto `CarAppService`/`Session`. (CarPlay entitlement and the Android Auto `CarAppService` are declared in the host app, as required by both platforms.)

## 1.4.0
* **Alternative-route selection on iOS** — `selectAlternativeRoute(index)` now promotes the chosen route to primary on iOS too (via the v3 `NavigationRoutes.selecting(alternativeRoute:)` API), at parity with Android. Re-showcases and, if a trip is active, continues guidance along the new route.
* **Mid-trip stops on the embedded view** — `MapBoxNavigationViewController.addWayPoints(...)` appends intermediate stops to the route currently shown/navigated and recomputes it (Uber-style "add a stop"), on Android and iOS. Previously `addWayPoints` only worked for full-screen navigation.
* **Road avoidance on full-screen Android** — `MapBoxOptions.exclude` (toll/motorway/ferry/...) is now also honoured by the full-screen `startNavigation` path (it already worked on the embedded view and on iOS).
* Full-screen Android now also emits the `alternative_routes` event for parity with the embedded view.
* Offline maps & offline routing (`downloadOfflineRegion` / `removeOfflineRegion` / `getOfflineRegions`) continue to be supported on both platforms.

## 1.3.0
* Embedded view: **map markers from Dart** — `addMarkers`, `removeMarker`, `clearMarkers` draw colored circles (with an optional text label) on the map independently of the route, on both Android and iOS. Useful for passenger/driver/POI pins.
* **Route avoidance** — `MapBoxOptions.exclude` (e.g. `['toll', 'motorway', 'ferry']`) is now honoured when building routes (Android embedded + iOS).
* **Alternative routes** — after a successful build, an `alternative_routes` event delivers a list of `RouteAlternative` (index / distance / duration). `selectAlternativeRoute(index)` promotes one to primary (Android).
* **Richer progress data for custom UIs** — `RouteProgressEvent` now exposes `maneuverType`, `maneuverModifier`, and `upcomingInstruction` so a fully custom Flutter navigation UI can be built on top of the native map.

## 1.2.2
* iOS: full-screen free drive now has a close button to end the session and dismiss the screen.
* iOS: `addWayPoints` during an active full-screen trip updates the running trip in place (`startActiveGuidance`) instead of presenting a second navigation controller (which could fail with "already presenting").
* iOS: a custom `mapStyleUrlNight` is now applied to the full-screen, embedded and free-drive maps when the device is in dark mode (previously only the day style was used).

## 1.2.1
* iOS: pinned the Mapbox SDK to exact versions (Navigation 3.24.2 / Maps 11.24.2) so SPM resolution is deterministic and compiles cleanly; an open version range paired the SDK with a Maps build that failed under the CI Swift compiler.
* CI: the iOS build job now runs on macOS 15 and selects Xcode 16.4 (the toolchain the pinned Mapbox SDK is validated against).

## 1.2.0
* iOS: migrated to the Mapbox Navigation SDK v3 (Maps SDK v11) — rewritten against `MapboxNavigationProvider`, async `calculateRoutes`, `NavigationRoutes`, and the v3 `NavigationViewController`/`NavigationMapView`. `isV3` now returns `true` on iOS.
* iOS: distributed via Swift Package Manager (a `Package.swift` is shipped) because v3 has no CocoaPods release; host apps must enable Flutter's SPM support and target iOS 14+.
* iOS: added offline maps & offline routing — `downloadOfflineRegion`, `removeOfflineRegion`, `getOfflineRegions` with a shared tile store and `offline_region_*` progress events (parity with Android).
* iOS: removed the legacy v2-only sources (route selection view, Day/Night style subclasses, stubbed offline routing).
* CI: added a macOS `ios-build` job that compiles the example app through SPM.

## 1.1.0
* Maintained by NabuxAi.
* Android: implemented full-screen turn-by-turn navigation (`startNavigation`, `startFreeDrive`, `addWayPoints`) via a dedicated NavigationActivity — previously v3 only supported embedded navigation.
* Android: full-screen navigation now has a maneuver banner, trip-progress (ETA/distance/time) bar, spoken voice guidance, and recenter/mute controls (parity with the upstream Drop-In UI, which v3 removed).
* Android: implemented `simulateRoute` via a replay trip session so the puck drives along the route.
* Android: fixed the embedded navigation map rendering black by owning the MapView lifecycle.
* Android: added offline maps & offline routing — `downloadOfflineRegion`, `removeOfflineRegion`, `getOfflineRegions` with a shared tile store and progress events.
* Android: Mapbox Navigation SDK v3 (Maps SDK v11) is now the default; removed the `BIKO_MAPBOX_NAV_V3` build flag.
* Android: migrated to declarative Kotlin/Android Gradle plugins, Java 17, and the stable Navigation SDK 3.20.0.
* Stopped tracking generated `build/` artifacts.

## 1.0.1
* Expose `currentSpeed` (meters/second) on `RouteProgressEvent` for Android and iOS.
* Send the `arrived` flag on Android route progress events for parity with iOS.
* Draw origin/destination waypoint markers on the embedded iOS map when a route is built.
* Example app now displays current speed and ETA.

## 1.0.0
* Initial release of `flutter_mapbox_navigation_plus`.
* Support for latest Flutter versions.
* Support for latest Gradle and Android namespaces.
* Forked from `flutter_mapbox_navigation` 0.2.2.

## 0.2.2
* Fix issue with voice units in Android
* Fix BannerText, VoiceInstruction and Off Route Events

## 0.2.1
* Fix issue with setting the language in Android

## 0.2.0
* Update MapBox Android Version
* Resolve issue where Navigation Does Not Dismiss Activity on Cancel

## 0.1.9
* Android Day/Night Style Default Values [PR 272](https://github.com/eopeter/flutter_mapbox_navigation/pull/272)
* Fix iOS Embedded Clear Route Issue [PR 284](https://github.com/eopeter/flutter_mapbox_navigation/pull/284)
* Fix Route Events Not Sent [PR 288](https://github.com/eopeter/flutter_mapbox_navigation/pull/288)
* Set WayPoint IsSilent to default false

## 0.1.8
* Fix Android NavigationMode [261](https://github.com/eopeter/flutter_mapbox_navigation/pull/261)

## 0.1.7
* Fix Android mainClass entry Error

## 0.1.6
* Embedded Clear Route Bug Fix

## 0.1.5
* Bug Fixes [248](https://github.com/eopeter/flutter_mapbox_navigation/pull/248) and [250](https://github.com/eopeter/flutter_mapbox_navigation/pull/250)

## 0.1.4
* Android Send Cancel Event [235](https://github.com/eopeter/flutter_mapbox_navigation/pull/235)
* iOS Receive Feedback Sent to Mapbox on Dart Side; Ability to Turn On/Off Show Feedback [235](https://github.com/eopeter/flutter_mapbox_navigation/pull/235)
* Add Free Drive Mode [240](https://github.com/eopeter/flutter_mapbox_navigation/pull/240)

## 0.1.3
* Android Send Cancel Event [236](https://github.com/eopeter/flutter_mapbox_navigation/pull/236)

## 0.1.2
* Android embedded view now working [#225](https://github.com/eopeter/flutter_mapbox_navigation/pull/225)
* Fixes Progress Changed and Route Build Event Data serialization on Android [#227](https://github.com/eopeter/flutter_mapbox_navigation/pull/227)

## 0.1.1
* Android: move LeakCanary as DebugImplementation [#221](https://github.com/eopeter/flutter_mapbox_navigation/pull/221)
* Emit Route Data Upon Route Build [#218](https://github.com/eopeter/flutter_mapbox_navigation/pull/218)
* Implement Silent Waypoints [#214](https://github.com/eopeter/flutter_mapbox_navigation/pull/214)

## 0.1.0
* breaking changes
* Android Gradle Upgrade
* Bug Fixes
* MapBox Library Upgrade
* iOS MapBox Token Property Name in info.plist is now MBXAccessToken
* Embedded Nav Broken in Android - Working On It

## 0.0.26
* not implemented bug for onNextLegStart

## 0.0.25
* bug fixes

## 0.0.24
* bug fixes

## 0.0.22
* bug fixes

## 0.0.21
* Fix static analysis bug

## 0.0.20
* Upgrade Mapbox Libraries
* Upgrade to Null Safety

## 0.0.19
* Upgrade MapBox Android to v1.0.1
* Gradle Updates
* Bug Fixes

## 0.0.18
* Bug Fixes

## 0.0.17
* Offline Navigation
* Bug Fixes

## 0.0.16
* Refactoring with breaking changes. Sorry :-(
* Add Embedded Navigation
* Consolidated Navigation Options
* Add ability to change map style
* Can select alternate routes

## 0.0.15
* Remove Dialog at WayPoint Arrival
* Tweak iOS WayPoint navigation behavior to match Android
* Bug Fixes

## 0.0.14
* Bug Fixes

## 0.0.13
* Apply Dart Formats
* Added Some Documentation
* Bug Fixes

## 0.0.12
* Added Multi-Stop WayPoint Navigation
* More Detailed Progress Events like route leg and step details
* MapBox Version Updates

## 0.0.11
* Deprecated NavigationMode. Use MapBoxNavigationMode instead.
* Upgrade MapBox Libraries
* Android Gradle Update
* Bug Fixes

## 0.0.10
* Added ability to override the measurement system used in spoken instructions

## 0.0.9
* Added option to change default language. See example in Read Me. This is only the language for the spoken instruction.

## 0.0.8
* Plugin upgrade for Flutter 1.12

## 0.0.7
* Remove extraneous jars for Kotlin-Reflect Inserted to lib folder by Android Studio

## 0.0.6
* Android Bug Fix

## 0.0.5
*[Breaking] Constructor and Name Change. See Example
* Route Progress And Arrival Events on iOS. Android Pending.
* Ending Navigation
* Navigation Modes Support (driving, walking, cycling)
* Simulation Mode Support

## 0.0.4
* Gradle 5.4.1 Support
* Mapbox Update to Current Versions
* iOS 10 Minimum Requirement

## 0.0.3

* Added AndroidX Support

## 0.0.2

* Added Android Support

## 0.0.1

* Initial Release That Targets only iOS
