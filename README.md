[![Pub][pub_badge]][pub] [![BuyMeACoffee][buy_me_a_coffee_badge]][buy_me_a_coffee]

# flutter_mapbox_navigation_plus

**An updated fork of `flutter_mapbox_navigation`, maintained by [NabuxAi](https://github.com/NabuxAi), with support for the latest Flutter and Gradle versions and the Mapbox Navigation SDK v3 on Android.**

Add turn-by-turn navigation to your Flutter application using Mapbox. Never make your users leave your app when they need to navigate to a location.

> [!NOTE]
> This is a community-maintained fork of the original [flutter_mapbox_navigation](https://pub.dev/packages/flutter_mapbox_navigation) package by [eopeter](https://pub.dev/publishers/eopeter.com/packages). It has been updated by **NabuxAi** to support Flutter 3.x, the latest Android Gradle configurations, and the Mapbox Navigation SDK v3. The source code for this fork lives at [github.com/NabuxAi/flutter_mapbox_navigation_plus](https://github.com/NabuxAi/flutter_mapbox_navigation_plus).

## Features

* A full-fledged turn-by-turn navigation UI for Flutter that is ready to drop into your application.
* [Professionally designed map styles](https://www.mapbox.com/maps/) for daytime and nighttime driving.
* Worldwide driving, cycling, and walking directions powered by [open data](https://www.mapbox.com/about/open/) and user feedback.
* Traffic avoidance and proactive rerouting based on current conditions in [over 55 countries](https://docs.mapbox.com/help/how-mapbox-works/directions/#traffic-data).
* Natural-sounding turn instructions.
* [Support for over two dozen languages](https://docs.mapbox.com/ios/navigation/overview/localization-and-internationalization/).
* Real-time progress events including current speed (m/s), distance remaining, duration remaining (ETA), and an `arrived` flag — with parity across Android and iOS.
* Embeddable navigation view for both Android and iOS.

## What's New in This Fork

This fork tracks the upstream package while modernizing the Android toolchain and migrating to the Mapbox Navigation SDK v3. Highlights:

* **Mapbox Navigation SDK v3 by default on Android** (Maps SDK v11). The Android implementation now always compiles the v3 source set — the previous `BIKO_MAPBOX_NAV_V3` build flag has been removed. See [MIGRATION_V3.md](MIGRATION_V3.md) for details.
* **Modern Android build** — declarative Kotlin/Android Gradle plugins, Java 17, and the stable Navigation SDK 3.20.0.
* **`currentSpeed` (meters/second)** is now exposed on `RouteProgressEvent` for both Android and iOS.
* **`arrived` flag** is sent on Android route progress events for parity with iOS.
* **Origin/destination waypoint markers** are drawn on the embedded iOS map when a route is built.
* The example app now displays **current speed** and **ETA**.

> [!IMPORTANT]
> iOS v3 migration is still pending — see [MIGRATION_V3.md](MIGRATION_V3.md) for the current status.

## iOS Configuration

1. Go to your [Mapbox account dashboard](https://account.mapbox.com/) and create an access token that has the `DOWNLOADS:READ` scope. **PLEASE NOTE: This is not the same as your production Mapbox API token. Keep it private and do not place it in any `Info.plist` file.** Create a file named `.netrc` in your home directory if it does not already exist, then add the following lines to the end of the file:
   ```
   machine api.mapbox.com
     login mapbox
     password PRIVATE_MAPBOX_API_TOKEN
   ```
   where `PRIVATE_MAPBOX_API_TOKEN` is your Mapbox API token with the `DOWNLOADS:READ` scope.

2. Mapbox APIs and vector tiles require a Mapbox account and API access token. In the project editor, select the application target, then go to the Info tab. Under the "Custom iOS Target Properties" section, set `MBXAccessToken` to your access token. You can obtain an access token from the [Mapbox account page](https://account.mapbox.com/access-tokens/).

3. In order for the SDK to track the user's location as they move along the route, set `NSLocationWhenInUseUsageDescription` to:
   > Shows your location on the map and helps improve OpenStreetMap.

4. Users expect the SDK to continue tracking their location and delivering audible instructions even while a different application is visible or the device is locked. Go to the Capabilities tab. Under the Background Modes section, enable "Audio, AirPlay, and Picture in Picture" and "Location updates". (Alternatively, add the `audio` and `location` values to the `UIBackgroundModes` array in the Info tab.)

## Android Configuration

1. Mapbox APIs and vector tiles require a Mapbox account and API access token. Add a new resource file called `mapbox_access_token.xml` at `<YOUR_FLUTTER_APP_ROOT>/android/app/src/main/res/values/mapbox_access_token.xml`. Then add a string resource named `mapbox_access_token` with your token as its value, as shown below. You can obtain an access token from the [Mapbox account page](https://account.mapbox.com/access-tokens/).
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <resources xmlns:tools="http://schemas.android.com/tools">
       <string name="mapbox_access_token" translatable="false" tools:ignore="UnusedResources">ADD_MAPBOX_ACCESS_TOKEN_HERE</string>
   </resources>
   ```

2. Add the following permissions to the app-level Android Manifest:
   ```xml
   <manifest>
       ...
       <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
       <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
       <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
       ...
   </manifest>
   ```

3. Add the Mapbox Downloads token with the `downloads:read` scope to the `gradle.properties` file in your Android folder to enable downloading the Mapbox binaries from the repository. To keep this token out of source control, you can add it to the `gradle.properties` of your `GRADLE_HOME`, which is usually at `$USER_HOME/.gradle`. This token can be retrieved from your [Mapbox Dashboard](https://account.mapbox.com/access-tokens/). See the [Token Guide](https://docs.mapbox.com/accounts/guides/tokens/) to learn more about download tokens.
   ```text
   MAPBOX_DOWNLOADS_TOKEN=sk.XXXXXXXXXXXXXXX
   ```

   After adding the above, your `gradle.properties` file may look something like this:
   ```text
   org.gradle.jvmargs=-Xmx1536M
   android.useAndroidX=true
   android.enableJetifier=true
   MAPBOX_DOWNLOADS_TOKEN=sk.epe9nE9peAcmwNzKVNqSbFfp2794YtnNepe9nE9peAcmwNzKVNqSbFfp2794YtnN.-HrbMMQmLdHwYb8r
   ```

4. Update `MainActivity.kt` to extend `FlutterFragmentActivity` instead of `FlutterActivity`. Otherwise you will get `Caused by: java.lang.IllegalStateException: Please ensure that the hosting Context is a valid ViewModelStoreOwner`.
   ```kotlin
   //import io.flutter.embedding.android.FlutterActivity
   import io.flutter.embedding.android.FlutterFragmentActivity

   class MainActivity : FlutterFragmentActivity() {
   }
   ```

5. This fork builds against Java 17 and the Mapbox Navigation SDK v3 by default. Make sure your app uses a compatible Android Gradle Plugin and a JDK 17 toolchain.

> [!WARNING]
> Do not add `mapbox_maps_flutter` alongside this package in the same app. Doing so can cause Android duplicate-class checks to fail because of conflicting Maps SDK versions. See [MIGRATION_V3.md](MIGRATION_V3.md).

## Usage

### Set Default Route Options (Optional)

```dart
MapBoxNavigation.instance.setDefaultOptions(MapBoxOptions(
  initialLatitude: 36.1175275,
  initialLongitude: -115.1839524,
  zoom: 13.0,
  tilt: 0.0,
  bearing: 0.0,
  enableRefresh: false,
  alternatives: true,
  voiceInstructionsEnabled: true,
  bannerInstructionsEnabled: true,
  allowsUTurnAtWayPoints: true,
  mode: MapBoxNavigationMode.drivingWithTraffic,
  mapStyleUrlDay: "https://url_to_day_style",
  mapStyleUrlNight: "https://url_to_night_style",
  units: VoiceUnits.imperial,
  simulateRoute: true,
  language: "en",
));
```

### Listen for Events

```dart
MapBoxNavigation.instance.registerRouteEventListener(_onRouteEvent);

Future<void> _onRouteEvent(e) async {
  _distanceRemaining = await MapBoxNavigation.instance.getDistanceRemaining();
  _durationRemaining = await MapBoxNavigation.instance.getDurationRemaining();

  switch (e.eventType) {
    case MapBoxEvent.progress_change:
      final progressEvent = e.data as RouteProgressEvent;
      _arrived = progressEvent.arrived;
      _currentSpeed = progressEvent.currentSpeed; // meters/second
      if (progressEvent.currentStepInstruction != null) {
        _instruction = progressEvent.currentStepInstruction;
      }
      break;
    case MapBoxEvent.route_building:
    case MapBoxEvent.route_built:
      _routeBuilt = true;
      break;
    case MapBoxEvent.route_build_failed:
      _routeBuilt = false;
      break;
    case MapBoxEvent.navigation_running:
      _isNavigating = true;
      break;
    case MapBoxEvent.on_arrival:
      _arrived = true;
      if (!_isMultipleStop) {
        await Future.delayed(const Duration(seconds: 3));
        await _controller.finishNavigation();
      }
      break;
    case MapBoxEvent.navigation_finished:
    case MapBoxEvent.navigation_cancelled:
      _routeBuilt = false;
      _isNavigating = false;
      break;
    default:
      break;
  }

  // Refresh the UI.
  setState(() {});
}
```

### Begin Navigating

```dart
final cityHall = WayPoint(name: "City Hall", latitude: 42.886448, longitude: -78.878372);
final downtown = WayPoint(name: "Downtown Buffalo", latitude: 42.8866177, longitude: -78.8814924);

final wayPoints = <WayPoint>[cityHall, downtown];

await MapBoxNavigation.instance.startNavigation(wayPoints: wayPoints);
```

### Screenshots

| ![iOS View](screenshots/screenshot1.png?raw=true "iOS View") | ![Android View](screenshots/screenshot2.png?raw=true "Android View") |
|:---:|:---:|
| iOS View | Android View |

## Embedding the Navigation View

### Declare a Controller

```dart
late MapBoxNavigationViewController _controller;
```

### Add the Navigation View to the Widget Tree

```dart
Container(
  color: Colors.grey,
  child: MapBoxNavigationView(
    options: _options,
    onRouteEvent: _onRouteEvent,
    onCreated: (MapBoxNavigationViewController controller) async {
      _controller = controller;
    },
  ),
);
```

### Build a Route

```dart
final wayPoints = <WayPoint>[
  _origin,
  _stop1,
  _stop2,
  _stop3,
  _stop4,
  _origin,
];

await _controller.buildRoute(wayPoints: wayPoints);
```

### Start Navigation

```dart
await _controller.startNavigation();
```

## Offline Maps & Offline Navigation (Android)

The Android v3 implementation can download a region so that **both the map and
routing work without a network connection**. A single shared tile store backs the
map renderer and the Navigation SDK, so one download serves both.

Pick the area as an arbitrary polygon (or a bounding box) and listen for progress
through the normal route event listener:

```dart
// Listen for download progress / completion.
MapBoxNavigation.instance.registerRouteEventListener((event) {
  switch (event.eventType) {
    case MapBoxEvent.offline_region_progress:
      final data = event.data as Map<String, dynamic>;
      print('Offline ${data['id']}: ${data['progress']}%');
      break;
    case MapBoxEvent.offline_region_complete:
      print('Offline region ready');
      break;
    case MapBoxEvent.offline_region_error:
      print('Offline error: ${(event.data as Map)['message']}');
      break;
    default:
      break;
  }
});

// Download a rectangular region (map tiles + routing tiles).
await MapBoxNavigation.instance.downloadOfflineRegion(
  OfflineRegion.fromBounds(
    id: 'muscat',
    southWestLat: 23.55,
    southWestLng: 58.35,
    northEastLat: 23.65,
    northEastLng: 58.55,
    maxZoom: 16,
  ),
);

// ...or an arbitrary polygon ([longitude, latitude] pairs):
await MapBoxNavigation.instance.downloadOfflineRegion(
  OfflineRegion(
    id: 'custom-area',
    coordinates: const [
      [58.35, 23.55],
      [58.55, 23.55],
      [58.55, 23.65],
      [58.35, 23.65],
      [58.35, 23.55],
    ],
    maxZoom: 16,
  ),
);

// Manage downloaded regions.
final regions = await MapBoxNavigation.instance.getOfflineRegions();
await MapBoxNavigation.instance.removeOfflineRegion('muscat');
```

> [!NOTE]
> Higher `maxZoom` values dramatically increase the download size. iOS offline
> support is not yet implemented (see the roadmap).

### Additional iOS Configuration

Add the following to your `Info.plist` file:

```xml
<dict>
    ...
    <key>io.flutter.embedded_views_preview</key>
    <true/>
    ...
</dict>
```

### Embedded Navigation Screenshots

| ![Embedded iOS View](screenshots/screenshot3.png?raw=true "Embedded iOS View") | ![Embedded Android View](screenshots/screenshot4.png?raw=true "Embedded Android View") |
|:---:|:---:|
| Embedded iOS View | Embedded Android View |

## Roadmap

* [x] Android implementation
* [x] More settings such as navigation mode (driving, walking, etc.)
* [x] Stream events such as relevant navigation notifications, metrics, current location, etc.
* [x] Embeddable navigation view
* [x] Mapbox Navigation SDK v3 on Android
* [ ] Mapbox Navigation SDK v3 on iOS
* [x] Offline maps & routing on Android
* [ ] Offline maps & routing on iOS

## Maintainer

This fork is maintained by **NabuxAi** — [github.com/NabuxAi](https://github.com/NabuxAi).

<!-- Links -->
[pub_badge]: https://img.shields.io/pub/v/flutter_mapbox_navigation_plus.svg
[pub]: https://pub.dev/packages/flutter_mapbox_navigation_plus
[buy_me_a_coffee]: https://www.buymeacoffee.com/eopeter
[buy_me_a_coffee_badge]: https://img.buymeacoffee.com/button-api/?text=Donate&emoji=&slug=eopeter&button_colour=29b6f6&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=FFDD00
