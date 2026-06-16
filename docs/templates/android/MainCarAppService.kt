// Android Auto CarAppService template for flutter_mapbox_navigation_plus.
//
// Copy this into your Flutter app's android module under a `car/` package and
// declare it in AndroidManifest.xml (see docs/CARPLAY_ANDROID_AUTO.md). This is
// a TEMPLATE and is not part of the plugin build — Android Auto requires the
// service to be declared by the host app's manifest.
//
// Requires (app build.gradle, version must match the plugin's Nav SDK):
//   implementation "com.mapbox.navigationcore:android-auto-components-ndk27:3.20.0"

package com.example.yourapp.car

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class MainCarAppService : CarAppService() {

    // ALLOW_ALL_HOSTS is convenient for development. For production, validate
    // against Android Auto / Automotive OS signatures instead.
    override fun createHostValidator(): HostValidator =
        HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = MainCarSession()
}
