package com.eopeter.fluttermapboxnavigation.activity

import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.eopeter.fluttermapboxnavigation.FlutterMapboxNavigationPlugin
import com.eopeter.fluttermapboxnavigation.offline.MapboxOfflineManager
import com.mapbox.api.directions.v5.DirectionsCriteria
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.MapView
import com.mapbox.maps.Style
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.extensions.applyLanguageAndVoiceUnitOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.base.trip.model.RouteLegProgress
import com.mapbox.navigation.base.trip.model.RouteProgress
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.arrival.ArrivalObserver
import com.mapbox.navigation.core.directions.session.RoutesObserver
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.replay.route.ReplayRouteMapper
import com.mapbox.navigation.core.trip.session.BannerInstructionsObserver
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.core.trip.session.OffRouteObserver
import com.mapbox.navigation.core.trip.session.RouteProgressObserver
import com.mapbox.navigation.core.trip.session.VoiceInstructionsObserver
import com.mapbox.navigation.ui.maps.camera.NavigationCamera
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApi
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineView
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineApiOptions
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineViewOptions
import com.mapbox.navigation.voice.api.MapboxSpeechApi
import com.mapbox.navigation.voice.api.MapboxVoiceInstructionsPlayer
import com.mapbox.navigation.voice.model.SpeechAnnouncement
import com.mapbox.navigation.voice.model.SpeechError
import com.mapbox.navigation.voice.model.SpeechValue
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.locationcomponent.location
import org.json.JSONObject

/**
 * Full-screen turn-by-turn navigation for the v3 implementation.
 *
 * Launched from [FlutterMapboxNavigationPlugin] for `startNavigation` /
 * `startFreeDrive`. Being a real Activity, it is its own LifecycleOwner, so the
 * MapView renders without the lifecycle workaround the embedded view needs.
 * Route progress, arrival, voice and banner events are forwarded to Flutter
 * through the plugin's shared event channel.
 */
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapView: MapView
    private lateinit var bannerText: TextView

    private lateinit var viewportDataSource: MapboxNavigationViewportDataSource
    private lateinit var navigationCamera: NavigationCamera
    private val navigationLocationProvider = NavigationLocationProvider()
    private val routeLineApi = MapboxRouteLineApi(
        MapboxRouteLineApiOptions.Builder().vanishingRouteLineEnabled(true).build()
    )
    private lateinit var routeLineView: MapboxRouteLineView
    private val replayRouteMapper = ReplayRouteMapper()

    private var currentStyle: Style? = null
    private var hasArrived = false
    private var currentSpeed: Float? = null
    private var simulate = false
    private var voiceEnabled = true
    private var speechApi: MapboxSpeechApi? = null
    private var voiceInstructionsPlayer: MapboxVoiceInstructionsPlayer? = null

    private val voicePlayerCallback =
        com.mapbox.navigation.ui.base.util.MapboxNavigationConsumer<SpeechAnnouncement> { announcement ->
            speechApi?.clean(announcement)
        }

    private val speechCallback =
        com.mapbox.navigation.ui.base.util.MapboxNavigationConsumer<com.mapbox.bindgen.Expected<SpeechError, SpeechValue>> { expected ->
            if (expected.isValue) {
                voiceInstructionsPlayer?.play(expected.value!!.announcement!!, voicePlayerCallback)
            } else {
                voiceInstructionsPlayer?.play(expected.error!!.fallback!!, voicePlayerCallback)
            }
        }

    private val voiceObserver = VoiceInstructionsObserver { voiceInstructions ->
        FlutterMapboxNavigationPlugin.sendEvent("speech_announcement", voiceInstructions.announcement())
        if (voiceEnabled) speechApi?.generate(voiceInstructions, speechCallback)
    }

    private val bannerObserver = BannerInstructionsObserver { banner ->
        val text = banner.primary()?.text() ?: ""
        bannerText.text = text
        FlutterMapboxNavigationPlugin.sendEvent("banner_instruction", text)
    }

    private val locationObserver = object : LocationObserver {
        override fun onNewRawLocation(rawLocation: com.mapbox.common.location.Location) = Unit
        override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
            val enhanced = locationMatcherResult.enhancedLocation
            currentSpeed = enhanced.speed?.toFloat()
            navigationLocationProvider.changePosition(enhanced, locationMatcherResult.keyPoints)
            viewportDataSource.onLocationChanged(enhanced)
            viewportDataSource.evaluate()
        }
    }

    private val arrivalObserver = object : ArrivalObserver {
        override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
            hasArrived = true
            FlutterMapboxNavigationPlugin.sendEvent("on_arrival")
        }

        override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) = Unit
        override fun onWaypointArrival(routeProgress: RouteProgress) = Unit
    }

    private val offRouteObserver = OffRouteObserver { offRoute ->
        if (offRoute) FlutterMapboxNavigationPlugin.sendEvent("user_off_route")
    }

    private val routesObserver = RoutesObserver { result ->
        if (result.navigationRoutes.isNotEmpty()) {
            renderRoute(result.navigationRoutes)
        }
    }

    private val routeProgressObserver = RouteProgressObserver { routeProgress ->
        FlutterMapboxNavigationPlugin.distanceRemaining = routeProgress.distanceRemaining
        FlutterMapboxNavigationPlugin.durationRemaining = routeProgress.durationRemaining
        viewportDataSource.onRouteProgressChanged(routeProgress)
        viewportDataSource.evaluate()
        currentStyle?.let { style ->
            routeLineApi.updateWithRouteProgress(routeProgress) { result ->
                routeLineView.renderRouteLineUpdate(style, result)
            }
        }
        FlutterMapboxNavigationPlugin.sendEvent(
            "progress_change",
            mapOf(
                "arrived" to hasArrived,
                "distance" to routeProgress.distanceRemaining,
                "duration" to routeProgress.durationRemaining,
                "distanceTraveled" to routeProgress.distanceTraveled,
                "currentLegDistanceTraveled" to (routeProgress.currentLegProgress?.distanceTraveled ?: 0.0),
                "currentLegDistanceRemaining" to (routeProgress.currentLegProgress?.distanceRemaining ?: 0.0),
                "currentStepInstruction" to (
                    routeProgress.currentLegProgress?.currentStepProgress?.step?.maneuver()?.instruction() ?: ""
                    ),
                "legIndex" to routeProgress.currentLegProgress?.legIndex,
                "stepIndex" to 0,
                "isPrimary" to true,
                "currentSpeed" to currentSpeed
            )
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        active = this

        simulate = intent.getBooleanExtra("simulateRoute", false)
        voiceEnabled = intent.getBooleanExtra("voiceEnabled", true)
        val isFreeDrive = intent.getBooleanExtra("isFreeDrive", false)

        mapView = MapView(this)
        viewportDataSource = MapboxNavigationViewportDataSource(mapView.mapboxMap)
        navigationCamera = NavigationCamera(mapView.mapboxMap, mapView.camera, viewportDataSource)
        routeLineView = MapboxRouteLineView(
            MapboxRouteLineViewOptions.Builder(this).displaySoftGradientForTraffic(true).build()
        )

        setContentView(buildUi())

        val density = resources.displayMetrics.density
        viewportDataSource.options.followingFrameOptions.defaultPitch =
            intent.getDoubleExtra("tilt", 45.0)
        viewportDataSource.followingPadding =
            com.mapbox.maps.EdgeInsets(140.0 * density, 0.0, 200.0 * density, 0.0)

        ensureNavigationSdk()
        loadStyle()

        if (!isFreeDrive) {
            buildAndStartRoute()
        } else {
            startTripSession(simulate)
            navigationCamera.requestNavigationCameraToFollowing()
            FlutterMapboxNavigationPlugin.sendEvent("navigation_running")
        }
    }

    private fun buildUi(): View {
        val root = FrameLayout(this)
        root.addView(
            mapView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        bannerText = TextView(this).apply {
            setBackgroundColor(Color.parseColor("#CC000000"))
            setTextColor(Color.WHITE)
            textSize = 16f
            setPadding(32, 32, 32, 32)
            text = ""
        }
        root.addView(
            bannerText,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.TOP }
        )

        val endButton = Button(this).apply {
            text = "End"
            setOnClickListener { finishNavigation() }
        }
        root.addView(
            endButton,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = 48
            }
        )
        return root
    }

    private fun ensureNavigationSdk() {
        MapboxOfflineManager.initialize(applicationContext)
        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup {
                val builder = NavigationOptions.Builder(applicationContext)
                MapboxOfflineManager.configureRoutingTiles(builder)
                builder.build()
            }
        }
        MapboxNavigationApp.attach(this)

        val language = intent.getStringExtra("language") ?: "en"
        speechApi = MapboxSpeechApi(this, language)
        voiceInstructionsPlayer = MapboxVoiceInstructionsPlayer(this, language)

        mapView.location.setLocationProvider(navigationLocationProvider)
        mapView.location.enabled = true
        mapView.location.updateSettings {
            enabled = true
            pulsingEnabled = true
        }

        MapboxNavigationApp.current()?.apply {
            registerArrivalObserver(arrivalObserver)
            registerLocationObserver(locationObserver)
            registerRouteProgressObserver(routeProgressObserver)
            registerVoiceInstructionsObserver(voiceObserver)
            registerBannerInstructionsObserver(bannerObserver)
            registerOffRouteObserver(offRouteObserver)
            registerRoutesObserver(routesObserver)
        }
    }

    private fun loadStyle() {
        val requested = intent.getStringExtra("mapStyleUrlDay")
        val styleUri = if (requested.isNullOrBlank()) Style.STANDARD else requested
        mapView.mapboxMap.loadStyle(styleUri) {
            currentStyle = it
            FlutterMapboxNavigationPlugin.sendEvent("mapStyleLoaded")
        }
    }

    private fun navigationProfile(): String {
        return when (intent.getStringExtra("mode")) {
            "walking" -> DirectionsCriteria.PROFILE_WALKING
            "cycling" -> DirectionsCriteria.PROFILE_CYCLING
            "driving" -> DirectionsCriteria.PROFILE_DRIVING
            else -> DirectionsCriteria.PROFILE_DRIVING_TRAFFIC
        }
    }

    private fun buildAndStartRoute() {
        val lats = intent.getDoubleArrayExtra("lats") ?: DoubleArray(0)
        val lngs = intent.getDoubleArrayExtra("lngs") ?: DoubleArray(0)
        if (lats.size < 2 || lats.size != lngs.size) {
            FlutterMapboxNavigationPlugin.sendEvent("route_build_failed")
            finish()
            return
        }
        val waypoints = lats.indices.map { Point.fromLngLat(lngs[it], lats[it]) }

        val navigation = MapboxNavigationApp.current()
        if (navigation == null) {
            FlutterMapboxNavigationPlugin.sendEvent("route_build_failed")
            finish()
            return
        }

        val language = intent.getStringExtra("language")
        val units = intent.getStringExtra("units")
        val options = RouteOptions.builder()
            .applyDefaultNavigationOptions(navigationProfile())
            .applyLanguageAndVoiceUnitOptions(this)
            .apply {
                if (!language.isNullOrBlank()) language(language)
                if (!units.isNullOrBlank()) voiceUnits(units)
            }
            .coordinatesList(waypoints)
            .alternatives(intent.getBooleanExtra("alternatives", false))
            .build()

        FlutterMapboxNavigationPlugin.sendEvent("route_building")
        navigation.requestRoutes(
            options,
            object : NavigationRouterCallback {
                override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                    FlutterMapboxNavigationPlugin.sendEvent("route_build_cancelled")
                }

                override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
                    FlutterMapboxNavigationPlugin.sendEvent("route_build_failed")
                }

                override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                    hasArrived = false
                    navigation.setNavigationRoutes(routes)
                    renderRoute(routes)
                    FlutterMapboxNavigationPlugin.sendEvent("route_built")
                    startTripSession(simulate)
                    if (simulate) startSimulation(navigation, routes.first())
                    navigationCamera.requestNavigationCameraToFollowing()
                    FlutterMapboxNavigationPlugin.sendEvent("navigation_running")
                }
            }
        )
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    private fun startTripSession(simulate: Boolean) {
        val navigation = MapboxNavigationApp.current() ?: return
        if (simulate) navigation.startReplayTripSession() else navigation.startTripSession()
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    private fun startSimulation(navigation: MapboxNavigation, route: NavigationRoute) {
        val replayer = navigation.mapboxReplayer
        replayer.stop()
        replayer.clearEvents()
        val events = replayRouteMapper.mapDirectionsRouteGeometry(route.directionsRoute)
        if (events.isEmpty()) return
        replayer.pushEvents(events)
        replayer.seekTo(events.first())
        replayer.play()
    }

    private fun renderRoute(routes: List<NavigationRoute>) {
        val style = currentStyle ?: return
        if (routes.isEmpty()) return
        routeLineApi.setNavigationRoutes(routes) { value ->
            routeLineView.renderRouteDrawData(style, value)
        }
        viewportDataSource.onRouteChanged(routes.first())
        viewportDataSource.evaluate()
    }

    /** Insert additional waypoints into the ongoing route (best effort). */
    fun addWaypoints(lats: DoubleArray, lngs: DoubleArray) {
        val navigation = MapboxNavigationApp.current() ?: return
        val current = navigation.getNavigationRoutes().firstOrNull() ?: return
        val existing = current.routeOptions?.coordinatesList()?.toMutableList() ?: return
        lats.indices.forEach { existing.add(Point.fromLngLat(lngs[it], lats[it])) }
        val options = current.routeOptions!!.toBuilder().coordinatesList(existing).build()
        navigation.requestRoutes(
            options,
            object : NavigationRouterCallback {
                override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) = Unit
                override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) = Unit
                override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                    navigation.setNavigationRoutes(routes)
                    renderRoute(routes)
                }
            }
        )
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    private fun finishNavigation() {
        MapboxNavigationApp.current()?.mapboxReplayer?.apply {
            stop()
            clearEvents()
        }
        MapboxNavigationApp.current()?.stopTripSession()
        FlutterMapboxNavigationPlugin.sendEvent("navigation_cancelled")
        FlutterMapboxNavigationPlugin.sendEvent("navigation_finished")
        finish()
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    override fun onDestroy() {
        active = null
        MapboxNavigationApp.current()?.apply {
            unregisterArrivalObserver(arrivalObserver)
            unregisterLocationObserver(locationObserver)
            unregisterRouteProgressObserver(routeProgressObserver)
            unregisterVoiceInstructionsObserver(voiceObserver)
            unregisterBannerInstructionsObserver(bannerObserver)
            unregisterOffRouteObserver(offRouteObserver)
            unregisterRoutesObserver(routesObserver)
            mapboxReplayer.stop()
            mapboxReplayer.clearEvents()
            stopTripSession()
        }
        MapboxNavigationApp.detach(this)
        speechApi?.cancel()
        voiceInstructionsPlayer?.shutdown()
        routeLineApi.cancel()
        routeLineView.cancel()
        super.onDestroy()
    }

    companion object {
        /** Reference to the running activity so the plugin can add waypoints. */
        var active: NavigationActivity? = null
    }
}
