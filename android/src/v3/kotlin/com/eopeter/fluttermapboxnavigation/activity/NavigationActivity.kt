package com.eopeter.fluttermapboxnavigation.activity

import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import com.eopeter.fluttermapboxnavigation.FlutterMapboxNavigationPlugin
import com.eopeter.fluttermapboxnavigation.offline.MapboxOfflineManager
import com.mapbox.api.directions.v5.DirectionsCriteria
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.Style
import com.mapbox.navigation.base.formatter.DistanceFormatterOptions
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
import com.mapbox.navigation.core.formatter.MapboxDistanceFormatter
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.replay.route.ReplayRouteMapper
import com.mapbox.navigation.core.trip.session.BannerInstructionsObserver
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.core.trip.session.OffRouteObserver
import com.mapbox.navigation.core.trip.session.RouteProgressObserver
import com.mapbox.navigation.core.trip.session.VoiceInstructionsObserver
import com.mapbox.navigation.tripdata.maneuver.api.MapboxManeuverApi
import com.mapbox.navigation.tripdata.progress.api.MapboxTripProgressApi
import com.mapbox.navigation.tripdata.progress.model.DistanceRemainingFormatter
import com.mapbox.navigation.tripdata.progress.model.EstimatedTimeToArrivalFormatter
import com.mapbox.navigation.tripdata.progress.model.PercentDistanceTraveledFormatter
import com.mapbox.navigation.tripdata.progress.model.TimeRemainingFormatter
import com.mapbox.navigation.tripdata.progress.model.TripProgressUpdateFormatter
import com.mapbox.navigation.tripdata.speedlimit.api.MapboxSpeedInfoApi
import com.mapbox.navigation.ui.components.maneuver.view.MapboxManeuverView
import com.mapbox.navigation.ui.components.speedlimit.view.MapboxSpeedInfoView
import com.mapbox.navigation.ui.components.tripprogress.view.MapboxTripProgressView
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
import com.mapbox.navigation.voice.model.SpeechVolume
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.locationcomponent.location
import com.mapbox.maps.plugin.scalebar.scalebar

/**
 * Full-screen turn-by-turn navigation for the v3 implementation.
 *
 * Launched from [FlutterMapboxNavigationPlugin] for `startNavigation` /
 * `startFreeDrive`. Being a real Activity, it is its own LifecycleOwner, so the
 * MapView renders without the lifecycle workaround the embedded view needs.
 *
 * Provides the turn-by-turn experience the upstream Drop-In UI did (which was
 * removed in Navigation SDK v3): a maneuver banner with icons, a trip-progress
 * bar (ETA / distance / time), spoken voice guidance, route line, a following
 * camera, plus recenter / mute / end controls. Route, progress, arrival, voice
 * and banner events are also forwarded to Flutter.
 */
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapView: MapView
    private lateinit var maneuverView: MapboxManeuverView
    private lateinit var tripProgressView: MapboxTripProgressView
    private lateinit var speedInfoView: MapboxSpeedInfoView
    private val speedInfoApi by lazy { MapboxSpeedInfoApi() }
    private var routeLats = DoubleArray(0)
    private var routeLngs = DoubleArray(0)

    private lateinit var viewportDataSource: MapboxNavigationViewportDataSource
    private lateinit var navigationCamera: NavigationCamera
    private val navigationLocationProvider = NavigationLocationProvider()
    private val routeLineApi = MapboxRouteLineApi(
        MapboxRouteLineApiOptions.Builder().vanishingRouteLineEnabled(true).build()
    )
    private lateinit var routeLineView: MapboxRouteLineView
    private val replayRouteMapper = ReplayRouteMapper()

    private val distanceFormatterOptions by lazy {
        DistanceFormatterOptions.Builder(this).build()
    }
    private val maneuverApi by lazy {
        MapboxManeuverApi(MapboxDistanceFormatter(distanceFormatterOptions))
    }
    private val tripProgressApi by lazy {
        MapboxTripProgressApi(
            TripProgressUpdateFormatter.Builder(this)
                .distanceRemainingFormatter(DistanceRemainingFormatter(distanceFormatterOptions))
                .timeRemainingFormatter(TimeRemainingFormatter(this))
                .percentRouteTraveledFormatter(PercentDistanceTraveledFormatter())
                .estimatedTimeToArrivalFormatter(EstimatedTimeToArrivalFormatter(this))
                .build()
        )
    }

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
        FlutterMapboxNavigationPlugin.sendEvent("banner_instruction", banner.primary()?.text() ?: "")
    }

    private val locationObserver = object : LocationObserver {
        override fun onNewRawLocation(rawLocation: com.mapbox.common.location.Location) = Unit
        override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
            val enhanced = locationMatcherResult.enhancedLocation
            currentSpeed = enhanced.speed?.toFloat()
            navigationLocationProvider.changePosition(enhanced, locationMatcherResult.keyPoints)
            viewportDataSource.onLocationChanged(enhanced)
            viewportDataSource.evaluate()
            // Speed limit / current speed indicator (the "speedometer").
            speedInfoApi.updatePostedAndCurrentSpeed(
                locationMatcherResult,
                distanceFormatterOptions
            )?.let { speedInfoView.render(it) }
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

        // Maneuver banner (turn icon + instruction + distance).
        maneuverView.renderManeuvers(maneuverApi.getManeuvers(routeProgress))
        // Trip progress bar (ETA / distance / time remaining).
        tripProgressView.render(tripProgressApi.getTripProgress(routeProgress))

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
        routeLats = intent.getDoubleArrayExtra("lats") ?: DoubleArray(0)
        routeLngs = intent.getDoubleArrayExtra("lngs") ?: DoubleArray(0)

        mapView = MapView(this)
        // Hide the scale bar ruler (matches the upstream Drop-In look).
        mapView.scalebar.enabled = false
        viewportDataSource = MapboxNavigationViewportDataSource(mapView.mapboxMap)
        navigationCamera = NavigationCamera(mapView.mapboxMap, mapView.camera, viewportDataSource)
        routeLineView = MapboxRouteLineView(
            MapboxRouteLineViewOptions.Builder(this).displaySoftGradientForTraffic(true).build()
        )

        // Start the camera on a real location (route origin / supplied initial
        // point) instead of the default zoomed-out globe, which is slow to load.
        val initLat = intent.getDoubleExtra("initialLatitude", Double.NaN)
        val initLng = intent.getDoubleExtra("initialLongitude", Double.NaN)
        val initZoom = intent.getDoubleExtra("zoom", 15.0)
        val initialCenter = when {
            !initLat.isNaN() && !initLng.isNaN() -> Point.fromLngLat(initLng, initLat)
            routeLats.isNotEmpty() -> Point.fromLngLat(routeLngs[0], routeLats[0])
            else -> null
        }
        if (initialCenter != null) {
            mapView.mapboxMap.setCamera(
                CameraOptions.Builder().center(initialCenter).zoom(initZoom).build()
            )
        }

        setContentView(buildUi())

        val density = resources.displayMetrics.density
        viewportDataSource.options.followingFrameOptions.defaultPitch =
            intent.getDoubleExtra("tilt", 45.0)
        viewportDataSource.followingPadding =
            com.mapbox.maps.EdgeInsets(180.0 * density, 0.0, 180.0 * density, 0.0)

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
        val density = resources.displayMetrics.density
        val root = FrameLayout(this)
        root.addView(
            mapView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        maneuverView = MapboxManeuverView(this)
        root.addView(
            maneuverView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.TOP }
        )

        tripProgressView = MapboxTripProgressView(this)
        root.addView(
            tripProgressView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.BOTTOM }
        )

        // Speed limit / current speed indicator (bottom-left, above progress bar).
        speedInfoView = MapboxSpeedInfoView(this)
        root.addView(
            speedInfoView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.START
                bottomMargin = (96 * density).toInt()
                marginStart = (12 * density).toInt()
            }
        )

        // Right-side control stack: mute, recenter, end.
        val muteButton = Button(this).apply {
            text = if (voiceEnabled) "Mute" else "Unmute"
            setOnClickListener { toggleVoice(this) }
        }
        val recenterButton = Button(this).apply {
            text = "Recenter"
            setOnClickListener {
                navigationCamera.requestNavigationCameraToFollowing()
                FlutterMapboxNavigationPlugin.sendEvent(
                    "camera_state_changed",
                    mapOf("state" to "following")
                )
            }
        }
        val endButton = Button(this).apply {
            text = "End"
            setOnClickListener { finishNavigation() }
        }
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(muteButton)
            addView(recenterButton)
            addView(endButton)
        }
        root.addView(
            controls,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                marginEnd = (12 * density).toInt()
            }
        )
        return root
    }

    private fun toggleVoice(button: Button) {
        voiceEnabled = !voiceEnabled
        voiceInstructionsPlayer?.volume(SpeechVolume(if (voiceEnabled) 1f else 0f))
        button.text = if (voiceEnabled) "Mute" else "Unmute"
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
        val lats = routeLats
        val lngs = routeLngs
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
        val excludeList = intent.getStringArrayExtra("exclude")?.toList()
        val options = RouteOptions.builder()
            .applyDefaultNavigationOptions(navigationProfile())
            .applyLanguageAndVoiceUnitOptions(this)
            .apply {
                if (!language.isNullOrBlank()) language(language)
                if (!units.isNullOrBlank()) voiceUnits(units)
                if (!excludeList.isNullOrEmpty()) excludeList(excludeList)
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
                    sendAlternatives(routes)
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

    /** Emit a summary (index / distance / duration) of every returned route. */
    private fun sendAlternatives(routes: List<NavigationRoute>) {
        if (routes.isEmpty()) return
        val list = routes.mapIndexed { index, route ->
            mapOf(
                "index" to index,
                "distance" to route.directionsRoute.distance(),
                "duration" to route.directionsRoute.duration(),
                "isPrimary" to (index == 0)
            )
        }
        FlutterMapboxNavigationPlugin.sendEvent("alternative_routes", list)
    }

    /** Insert additional waypoints into the ongoing route (best effort). */
    fun addWaypoints(lats: DoubleArray, lngs: DoubleArray) {
        val navigation = MapboxNavigationApp.current() ?: return
        val current = navigation.getNavigationRoutes().firstOrNull() ?: return
        val routeOptions = current.directionsRoute.routeOptions() ?: return
        val existing = routeOptions.coordinatesList().toMutableList()
        lats.indices.forEach { existing.add(Point.fromLngLat(lngs[it], lats[it])) }
        val options = routeOptions.toBuilder().coordinatesList(existing).build()
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
        maneuverApi.cancel()
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
