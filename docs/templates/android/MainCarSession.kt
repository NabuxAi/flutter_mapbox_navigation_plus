// Android Auto Session template for flutter_mapbox_navigation_plus.
//
// Copy this into your Flutter app's android module under a `car/` package.
// TEMPLATE only — not compiled by the plugin. See docs/CARPLAY_ANDROID_AUTO.md.
//
// It attaches Mapbox's car map + screen manager to the SAME MapboxNavigationApp
// the plugin uses, so the phone and the car head unit share one trip session,
// one route and one offline tile store.

package com.example.yourapp.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.mapbox.maps.MapInitOptions
import com.mapbox.maps.extension.androidauto.MapboxCarMap
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.ui.androidauto.MapboxCarContext
import com.mapbox.navigation.ui.androidauto.map.MapboxCarMapLoader
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreen
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreenManager

class MainCarSession : Session() {

    private val carMapLoader = MapboxCarMapLoader()
    private val mapboxCarMap = MapboxCarMap().registerObserver(carMapLoader)
    private val mapboxCarContext = MapboxCarContext(lifecycle, mapboxCarMap)

    init {
        mapboxCarContext.prepareScreens()

        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                if (!MapboxNavigationApp.isSetup()) {
                    MapboxNavigationApp.setup(
                        NavigationOptions.Builder(carContext).build()
                    )
                }
                MapboxNavigationApp.attach(owner)
                mapboxCarMap.setup(carContext, MapInitOptions(context = carContext))
            }

            override fun onDestroy(owner: LifecycleOwner) {
                MapboxNavigationApp.detach(owner)
                mapboxCarMap.clearObservers()
            }
        })
    }

    override fun onCreateScreen(intent: Intent): Screen {
        // Resume whatever screen the SDK was last on (free drive by default).
        val key = MapboxScreenManager.current()?.key ?: MapboxScreen.FREE_DRIVE
        return mapboxCarContext.mapboxScreenManager.createScreen(key)
    }
}
