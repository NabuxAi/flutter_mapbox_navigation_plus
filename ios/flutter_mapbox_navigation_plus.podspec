#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_mapbox_navigation_plus.podspec` to validate before publishing.
#
# NOTE: Mapbox Navigation SDK v3 for iOS is distributed exclusively via Swift
# Package Manager — there is no CocoaPods release. This podspec therefore only
# declares the Flutter dependency and points at the SPM-style Sources directory
# so Flutter tooling keeps working. The Mapbox v3 SDK itself is resolved through
# `ios/flutter_mapbox_navigation_plus/Package.swift`, which requires the host app
# to enable Flutter's Swift Package Manager support. See README "iOS Configuration".
#
Pod::Spec.new do |s|
  s.name             = 'flutter_mapbox_navigation_plus'
  s.version          = '1.0.0'
  s.summary          = 'An updated fork of flutter_mapbox_navigation with support for the latest Flutter versions and the Mapbox Navigation SDK v3.'
  s.description      = <<-DESC
An updated fork of flutter_mapbox_navigation with support for the latest Flutter versions and the Mapbox Navigation SDK v3 on Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/NabuxAi/flutter_mapbox_navigation_plus'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'NabuxAi' => 'eopeter@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_mapbox_navigation_plus/Sources/flutter_mapbox_navigation_plus/**/*.swift'
  s.dependency 'Flutter'
  # Navigation SDK v3 requires iOS 14+.
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
