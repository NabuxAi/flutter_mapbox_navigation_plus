# CarPlay & Android Auto

This guide explains how to project `flutter_mapbox_navigation_plus` onto a car
head unit with **Apple CarPlay** (iOS) and **Android Auto**.

> **Why this lives in your app, not the plugin.** Both platforms require the car
> integration to be declared and owned by the *host application*:
>
> - **CarPlay** needs a CarPlay **entitlement granted by Apple** to your app's
>   bundle id, plus a CarPlay **scene delegate** registered in your app's
>   `Info.plist`. Entitlements and scene manifests cannot be vendored by a
>   Flutter plugin.
> - **Android Auto** needs a `CarAppService` declared in your app's
>   `AndroidManifest.xml`, the `androidx.car.app` host validator, and a
>   foreground-service permission — all app-level declarations.
>
> The plugin's job is to expose the **single shared Mapbox navigation session**
> so the car screen and the phone stay in sync (same route, same guidance, same
> offline tiles). The car UI itself is the Mapbox Navigation SDK's own
> CarPlay / Android Auto UI — you wire it up with the small templates below.

Ready-to-copy templates live in [`docs/templates/`](templates/).

---

## Apple CarPlay (iOS)

### 1. Get the entitlement
Request a CarPlay entitlement from Apple for your Apple Developer account
(navigation apps use `com.apple.developer.carplay.navigation`). Add it to your
app's `Runner.entitlements`:

```xml
<key>com.apple.developer.carplay.navigation</key>
<true/>
```

### 2. Register the CarPlay scene
Add a `CPTemplateApplicationSceneSessionRoleApplication` scene to
`ios/Runner/Info.plist`:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
  <key>UISceneConfigurations</key>
  <dict>
    <key>CPTemplateApplicationSceneSessionRoleApplication</key>
    <array>
      <dict>
        <key>UISceneConfigurationName</key>
        <string>CarPlay Configuration</string>
        <key>UISceneDelegateClassName</key>
        <string>Runner.CarPlaySceneDelegate</string>
      </dict>
    </array>
  </dict>
</dict>
```

### 3. Add the scene delegate
Copy [`docs/templates/ios/CarPlaySceneDelegate.swift`](templates/ios/CarPlaySceneDelegate.swift)
into `ios/Runner/`. It builds a `CarPlayManager` against the **same provider the
plugin uses**:

```swift
import flutter_mapbox_navigation_plus // NavigationProviderHolder
...
let provider = NavigationProviderHolder.shared.current
self.carPlayManager = CarPlayManager(navigationProvider: provider)
```

Because the provider is shared, a route built from Flutter is immediately
available on the CarPlay screen, and offline tiles downloaded with
`downloadOfflineRegion` work in the car too.

> CarPlay cannot be tested in the iOS Simulator's normal mode — use
> **Xcode ▸ I/O ▸ External Displays ▸ CarPlay** or a real head unit.

---

## Android Auto

### 1. Add the dependency (app `build.gradle`)
The Android Auto artifact version **must match the Navigation SDK version** the
plugin uses (currently `3.20.0`). Pick the `ndk27`/`ndk25` flavor that matches
your NDK:

```groovy
implementation "com.mapbox.navigationcore:android-auto-components-ndk27:3.20.0"
```

### 2. Manifest (app `AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<application ...>
  <meta-data
      android:name="com.google.android.gms.car.application"
      android:resource="@xml/automotive_app_desc" />

  <service
      android:name=".car.MainCarAppService"
      android:exported="true"
      android:foregroundServiceType="location">
    <intent-filter>
      <action android:name="androidx.car.app.CarAppService" />
      <category android:name="androidx.car.app.category.NAVIGATION" />
    </intent-filter>
  </service>
</application>
```

### 3. Add the car service + session
Copy [`docs/templates/android/MainCarAppService.kt`](templates/android/MainCarAppService.kt)
and [`docs/templates/android/MainCarSession.kt`](templates/android/MainCarSession.kt)
into your app under a `car/` package. They wire Mapbox's `MapboxCarMap` +
`MapboxScreenManager` to the shared `MapboxNavigationApp`, which the plugin also
drives — so phone and car share the same trip session.

`automotive_app_desc.xml` is shipped by the Mapbox Android Auto artifact; you do
not need to author it.

> Test with the **Desktop Head Unit (DHU)** from the Android Auto SDK, or a real
> head unit with developer mode enabled.

---

## What syncs automatically

| Concern | Shared? | How |
| --- | --- | --- |
| Active route / guidance | ✅ | Same `MapboxNavigationProvider` (iOS) / `MapboxNavigationApp` (Android) |
| Offline map + routing tiles | ✅ | Same tile store |
| Voice instructions | ✅ | Driven by the shared trip session |
| Flutter map markers (`addMarkers`) | ❌ | Phone-screen only (car UI is the SDK's own templates) |

## Limitations
- The car experience uses the **Mapbox SDK's built-in CarPlay / Android Auto
  UI**, not a custom Flutter UI (Flutter widgets cannot render on the car
  surface).
- Entitlement (CarPlay) and head-unit testing are the app owner's
  responsibility and cannot be validated by this repository's CI.
