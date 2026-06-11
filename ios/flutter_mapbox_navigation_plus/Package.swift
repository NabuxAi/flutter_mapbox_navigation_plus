// swift-tools-version: 5.9
// The Mapbox Navigation SDK v3 for iOS is distributed exclusively via Swift
// Package Manager (there is no CocoaPods release of v3). The plugin therefore
// ships this Package.swift so apps that have Flutter's Swift Package Manager
// support enabled can resolve the SDK. The accompanying `.podspec` is kept for
// Flutter tooling compatibility, but a CocoaPods-only app cannot pull the v3
// SDK — see README "iOS Configuration".
import PackageDescription

let package = Package(
    name: "flutter_mapbox_navigation_plus",
    platforms: [
        .iOS("14.0")
    ],
    products: [
        .library(
            name: "flutter-mapbox-navigation-plus",
            targets: ["flutter_mapbox_navigation_plus"]
        )
    ],
    dependencies: [
        // Mapbox Navigation SDK v3 (Navigation Core + UIKit drop-in UI).
        // Pinned to an exact release so resolution is deterministic: an open
        // range let SPM pair the SDK with a Maps version that does not compile
        // under the CI toolchain. v3.24.2 pins Maps SDK exactly 11.24.2
        // (compatible Xcode 16.4 — the CI job selects that Xcode).
        .package(
            url: "https://github.com/mapbox/mapbox-navigation-ios.git",
            exact: "3.24.2"
        ),
        // Maps SDK v11 — required for the offline manager (OfflineManager,
        // TilesetDescriptorOptions, StylePackLoadOptions) and the embedded
        // NavigationMapView styling. Pinned to the exact version the Navigation
        // SDK above depends on, so both resolve to the same Maps release.
        .package(
            url: "https://github.com/mapbox/mapbox-maps-ios.git",
            exact: "11.24.2"
        )
    ],
    targets: [
        .target(
            name: "flutter_mapbox_navigation_plus",
            dependencies: [
                .product(name: "MapboxNavigationCore", package: "mapbox-navigation-ios"),
                .product(name: "MapboxNavigationUIKit", package: "mapbox-navigation-ios"),
                .product(name: "MapboxDirections", package: "mapbox-navigation-ios"),
                .product(name: "MapboxMaps", package: "mapbox-maps-ios")
            ]
        )
    ]
)
