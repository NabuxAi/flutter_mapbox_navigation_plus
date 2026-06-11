package com.eopeter.fluttermapboxnavigation.models.views

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.eopeter.fluttermapboxnavigation.FlutterMapboxNavigationPlugin
import com.mapbox.api.directions.v5.DirectionsCriteria
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.api.directions.v5.models.BannerInstructions
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.ClickInteraction
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.MapView
import com.mapbox.maps.MapboxExperimental
import com.mapbox.maps.Style
import com.mapbox.maps.interactions.standard.generated.StandardBuildingsState
import com.mapbox.maps.interactions.standard.generated.StandardPoiState
import com.mapbox.maps.interactions.standard.generated.standardBuildings
import com.mapbox.maps.interactions.standard.generated.standardPoi
import com.mapbox.maps.plugin.gestures.gestures
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.extensions.applyLanguageAndVoiceUnitOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.base.trip.model.RouteLegProgress
import com.mapbox.navigation.base.trip.model.RouteProgress
import com.mapbox.navigation.core.arrival.ArrivalObserver
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.replay.route.ReplayRouteMapper
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.RouteProgressObserver
import com.mapbox.navigation.core.trip.session.VoiceInstructionsObserver
import com.mapbox.navigation.core.trip.session.BannerInstructionsObserver
import com.mapbox.navigation.core.trip.session.OffRouteObserver
import com.mapbox.navigation.core.directions.session.RoutesObserver
import com.mapbox.navigation.voice.api.MapboxSpeechApi
import com.mapbox.navigation.voice.api.MapboxVoiceInstructionsPlayer
import com.mapbox.navigation.voice.model.SpeechAnnouncement
import com.mapbox.navigation.voice.model.SpeechValue
import com.mapbox.navigation.voice.model.SpeechError
import com.mapbox.navigation.voice.options.MapboxSpeechApiOptions
import com.mapbox.navigation.voice.options.VoiceInstructionsPlayerOptions
import com.mapbox.navigation.ui.maps.camera.NavigationCamera
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApi
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineView
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineApiOptions
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineViewOptions
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.scalebar.scalebar
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject
import java.util.Locale
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider
import com.mapbox.maps.plugin.locationcomponent.location

class EmbeddedNavigationMapView(
    context: Context,
    private val activity: Activity,
    messenger: BinaryMessenger,
    viewId: Int,
    private val args: Any?
) : PlatformView,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    LifecycleOwner,
    SavedStateRegistryOwner {

    // Maps SDK v11 drives its GL renderer from the ViewTreeLifecycleOwner it
    // resolves at attach time. Inside a Flutter (Hybrid Composition) PlatformView
    // the hosting Activity is not guaranteed to be a LifecycleOwner (e.g. when the
    // app uses FlutterActivity instead of FlutterFragmentActivity), and even when
    // it is, the attach timing can leave the map without start/resume callbacks ->
    // the surface never draws and the user sees a black map while the ornaments
    // (logo/compass/scale) still render. Owning the lifecycle here and driving it
    // from the view's window-attach state makes rendering independent of the host.
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry

    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry

    private val root = FrameLayout(context)
    private val mapView = MapView(context)
    private val channel = MethodChannel(messenger, "flutter_mapbox_navigation/$viewId")
    private val events = EventChannel(messenger, "flutter_mapbox_navigation/$viewId/events")
    private val options = (args as? Map<*, *>) ?: emptyMap<String, Any>()
    private val viewportDataSource = MapboxNavigationViewportDataSource(mapView.mapboxMap)
    private val navigationLocationProvider = NavigationLocationProvider()
    private val navigationCamera = NavigationCamera(
        mapView.mapboxMap,
        mapView.camera,
        viewportDataSource
    )
    private val routeLineApi = MapboxRouteLineApi(
        MapboxRouteLineApiOptions.Builder()
            .vanishingRouteLineEnabled(true)
            .build()
    )
    private val routeLineView = MapboxRouteLineView(
        MapboxRouteLineViewOptions.Builder(context)
            .displaySoftGradientForTraffic(true)
            .build()
    )
    private var eventSink: EventChannel.EventSink? = null
    private var currentRoutes: List<NavigationRoute>? = null
    private var distanceRemaining: Float? = null
    private var durationRemaining: Double? = null
    private var hasArrived = false
    private var currentSpeed: Float? = null
    private var currentStyle: Style? = null
    private var voiceInstructionsEnabled = options["voiceInstructionsEnabled"] as? Boolean ?: true

    private var speechApi: MapboxSpeechApi? = null
    private var voiceInstructionsPlayer: MapboxVoiceInstructionsPlayer? = null
    private val replayRouteMapper = ReplayRouteMapper()

    private val voiceInstructionsPlayerCallback =
        com.mapbox.navigation.ui.base.util.MapboxNavigationConsumer<SpeechAnnouncement> { announcement ->
            speechApi?.clean(announcement)
        }

    private val speechCallback =
        com.mapbox.navigation.ui.base.util.MapboxNavigationConsumer<com.mapbox.bindgen.Expected<SpeechError, SpeechValue>> { expected ->
            if (expected.isValue) {
                val value = expected.value!!
                voiceInstructionsPlayer?.play(value.announcement!!, voiceInstructionsPlayerCallback)
            } else {
                val error = expected.error!!
                voiceInstructionsPlayer?.play(error.fallback!!, voiceInstructionsPlayerCallback)
            }
        }

    private val voiceInstructionObserver = VoiceInstructionsObserver { voiceInstructions ->
        sendEvent("speech_announcement", voiceInstructions.announcement())
        if (voiceInstructionsEnabled) {
            speechApi?.generate(voiceInstructions, speechCallback)
        }
    }

    private val bannerInstructionObserver = BannerInstructionsObserver { bannerInstructions ->
        sendEvent("banner_instruction", bannerInstructions.primary()?.text() ?: "")
    }

    private val locationObserver = object : LocationObserver {
        override fun onNewRawLocation(rawLocation: com.mapbox.common.location.Location) = Unit

        override fun onNewLocationMatcherResult(
            locationMatcherResult: LocationMatcherResult
        ) {
            val enhancedLocation = locationMatcherResult.enhancedLocation
            currentSpeed = enhancedLocation.speed?.toFloat()
            navigationLocationProvider.changePosition(
                enhancedLocation,
                locationMatcherResult.keyPoints
            )
            viewportDataSource.onLocationChanged(enhancedLocation)
            viewportDataSource.evaluate()
        }
    }

    private val arrivalObserver = object : ArrivalObserver {
        override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
            hasArrived = true
            sendEvent("on_arrival")
        }

        override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) = Unit

        override fun onWaypointArrival(routeProgress: RouteProgress) = Unit
    }

    private val offRouteObserver = OffRouteObserver { offRoute ->
        if (offRoute) {
            sendEvent("user_off_route")
        }
    }

    private val routesObserver = RoutesObserver { routeUpdateResult ->
        if (routeUpdateResult.navigationRoutes.isNotEmpty()) {
            sendEvent("reroute_along")
            val routes = routeUpdateResult.navigationRoutes
            currentRoutes = routes
            renderRoute(routes)
        }
    }

    private val routeProgressObserver = RouteProgressObserver { routeProgress ->
        distanceRemaining = routeProgress.distanceRemaining
        durationRemaining = routeProgress.durationRemaining
        viewportDataSource.onRouteProgressChanged(routeProgress)
        viewportDataSource.evaluate()
        currentStyle?.let { style ->
            routeLineApi.updateWithRouteProgress(routeProgress) { result ->
                routeLineView.renderRouteLineUpdate(style, result)
            }
        }
        sendEvent(
            "progress_change",
            mapOf(
                "arrived" to hasArrived,
                "distance" to routeProgress.distanceRemaining,
                "duration" to routeProgress.durationRemaining,
                "distanceTraveled" to routeProgress.distanceTraveled,
                "currentLegDistanceTraveled" to (
                    routeProgress.currentLegProgress?.distanceTraveled ?: 0.0
                    ),
                "currentLegDistanceRemaining" to (
                    routeProgress.currentLegProgress?.distanceRemaining ?: 0.0
                    ),
                "currentStepInstruction" to (
                    routeProgress.currentLegProgress
                        ?.currentStepProgress
                        ?.step
                        ?.maneuver()
                        ?.instruction()
                        ?: ""
                    ),
                "legIndex" to routeProgress.currentLegProgress?.legIndex,
                "stepIndex" to 0,
                "isPrimary" to true,
                "currentSpeed" to currentSpeed
            )
        )
    }

    init {
        root.addView(mapView)
        // Hide the scale bar ruler (matches the upstream Drop-In look).
        mapView.scalebar.enabled = false
        // Start on the caller-provided location instead of the zoomed-out globe
        // (which is slow to load). Falls back to leaving the default camera.
        (options["initialLatitude"] as? Double)?.let { lat ->
            (options["initialLongitude"] as? Double)?.let { lng ->
                mapView.mapboxMap.setCamera(
                    CameraOptions.Builder()
                        .center(Point.fromLngLat(lng, lat))
                        .zoom(options["zoom"] as? Double ?: 15.0)
                        .build()
                )
            }
        }
        // Bring up our own lifecycle and expose it (plus the SavedStateRegistry the
        // Maps SDK expects) on the view tree so the v11 renderer can start. See the
        // note on lifecycleRegistry above for why we don't rely on the Activity.
        savedStateRegistryController.performAttach()
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        root.setViewTreeLifecycleOwner(this)
        root.setViewTreeSavedStateRegistryOwner(this)
        mapView.setViewTreeLifecycleOwner(this)
        mapView.setViewTreeSavedStateRegistryOwner(this)
        // Drive the lifecycle to RESUMED only while the view is actually attached to
        // a window, so the GL surface is rendering exactly when it is on screen.
        root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {
                lifecycleRegistry.currentState = Lifecycle.State.RESUMED
            }

            override fun onViewDetachedFromWindow(v: View) {
                if (lifecycleRegistry.currentState != Lifecycle.State.DESTROYED) {
                    lifecycleRegistry.currentState = Lifecycle.State.CREATED
                }
            }
        })
        if (root.isAttachedToWindow) {
            lifecycleRegistry.currentState = Lifecycle.State.RESUMED
        }
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
        initializeNavigationSdk(context)
        loadInitialStyle()
        // Apply the caller-provided camera padding/zoom/tilt; without this the
        // options sent from Flutter were silently ignored.
        configureViewport()
        registerMapTap()
        registerMoveGesture()
    }

    override fun getView(): View = root

    override fun dispose() {
        navigationCamera.requestNavigationCameraToIdle()
        MapboxNavigationApp.current()?.unregisterArrivalObserver(arrivalObserver)
        MapboxNavigationApp.current()?.unregisterLocationObserver(locationObserver)
        MapboxNavigationApp.current()?.unregisterRouteProgressObserver(routeProgressObserver)
        MapboxNavigationApp.current()?.unregisterVoiceInstructionsObserver(voiceInstructionObserver)
        MapboxNavigationApp.current()?.unregisterBannerInstructionsObserver(bannerInstructionObserver)
        MapboxNavigationApp.current()?.unregisterOffRouteObserver(offRouteObserver)
        MapboxNavigationApp.current()?.unregisterRoutesObserver(routesObserver)
        stopSimulation()
        MapboxNavigationApp.current()?.stopTripSession()
        // Mirror the attach() in initializeNavigationSdk so the navigation app
        // releases this view's lifecycle owner instead of leaking it.
        MapboxNavigationApp.detach(this)
        speechApi?.cancel()
        voiceInstructionsPlayer?.shutdown()
        routeLineApi.cancel()
        routeLineView.cancel()
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
        // Tear the lifecycle down last; this drives MapView.onStop/onDestroy and
        // releases the GL surface and any lifecycle-scoped resources.
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun registerMoveGesture() {
        mapView.gestures.addOnMoveListener(object : com.mapbox.maps.plugin.gestures.OnMoveListener {
            override fun onMoveBegin(detector: com.mapbox.android.gestures.MoveGestureDetector) {
                navigationCamera.requestNavigationCameraToIdle()
                sendEvent("camera_state_changed", mapOf("state" to "idle"))
            }

            override fun onMove(detector: com.mapbox.android.gestures.MoveGestureDetector): Boolean {
                return false
            }

            override fun onMoveEnd(detector: com.mapbox.android.gestures.MoveGestureDetector) {
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "isV3" -> result.success(true)
            "initialize" -> {
                sendEvent("map_ready")
                result.success(true)
            }
            "buildRoute" -> {
                buildRoute(call, result)
            }
            "startNavigation" -> {
                val routes = currentRoutes
                val navigation = MapboxNavigationApp.current()
                if (!routes.isNullOrEmpty() && navigation != null) {
                    // A fresh navigation run never starts in the "arrived" state;
                    // reset in case the same view is restarted without rebuilding.
                    hasArrived = false
                    val simulate = options["simulateRoute"] as? Boolean ?: false
                    navigation.setNavigationRoutes(routes)
                    startTripSession(navigation, simulate)
                    if (simulate) {
                        startSimulation(navigation, routes.first())
                    }
                    navigationCamera.requestNavigationCameraToFollowing()
                    sendEvent("navigation_running")
                    result.success(true)
                } else {
                    sendEvent("route_build_failed")
                    result.success(false)
                }
            }
            "clearRoute",
            "finishNavigation" -> {
                currentRoutes = null
                stopSimulation()
                MapboxNavigationApp.current()?.setNavigationRoutes(emptyList())
                MapboxNavigationApp.current()?.stopTripSession()
                viewportDataSource.clearRouteData()
                viewportDataSource.evaluate()
                navigationCamera.requestNavigationCameraToIdle()
                clearRouteLine()
                sendEvent("navigation_cancelled")
                result.success(true)
            }
            "startFreeDrive" -> {
                val navigation = MapboxNavigationApp.current()
                if (navigation == null) {
                    result.success(false)
                    return
                }
                startTripSession(navigation)
                sendEvent("navigation_running")
                navigationCamera.requestNavigationCameraToFollowing()
                result.success(true)
            }
            "stopNavigation" -> {
                stopSimulation()
                MapboxNavigationApp.current()?.stopTripSession()
                sendEvent("navigation_cancelled")
                result.success(true)
            }
            "getDistanceRemaining" -> {
                result.success(distanceRemaining?.toDouble() ?: 0.0)
            }
            "getDurationRemaining" -> {
                result.success(durationRemaining ?: 0.0)
            }
            "recenter" -> {
                navigationCamera.requestNavigationCameraToFollowing()
                sendEvent("camera_state_changed", mapOf("state" to "following"))
                result.success(true)
            }
            "toggleVoiceInstructions" -> {
                val enabled = call.arguments as? Boolean ?: !voiceInstructionsEnabled
                voiceInstructionsEnabled = enabled
                if (!enabled) {
                    voiceInstructionsPlayer?.volume(
                        com.mapbox.navigation.voice.model.SpeechVolume(0f)
                    )
                } else {
                    voiceInstructionsPlayer?.volume(
                        com.mapbox.navigation.voice.model.SpeechVolume(1f)
                    )
                }
                result.success(enabled)
            }
            else -> result.notImplemented()
        }
    }

    private fun buildRoute(call: MethodCall, result: MethodChannel.Result) {
        hasArrived = false
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val waypointsMap = arguments["wayPoints"] as? Map<*, *>
        val waypoints = mutableListOf<Point>()

        waypointsMap?.values?.forEach {
            val wp = it as? Map<*, *>
            val lat = wp?.get("Latitude") as? Double
            val lng = wp?.get("Longitude") as? Double
            if (lat != null && lng != null) {
                waypoints.add(Point.fromLngLat(lng, lat))
            }
        }

        if (waypoints.size < 2) {
            result.error("INVALID_WAYPOINTS", "Need at least 2 waypoints", null)
            return
        }

        // Honour the language/units the caller configured instead of silently
        // falling back to the device locale for routing instructions.
        val routeLanguage = this.options["language"] as? String
        val routeUnits = this.options["units"] as? String

        val options = RouteOptions.builder()
            .applyDefaultNavigationOptions(navigationProfile(arguments))
            .applyLanguageAndVoiceUnitOptions(activity)
            .apply {
                if (!routeLanguage.isNullOrBlank()) language(routeLanguage)
                if (!routeUnits.isNullOrBlank()) voiceUnits(routeUnits)
            }
            .coordinatesList(waypoints)
            .alternatives(arguments["alternatives"] as? Boolean ?: false)
            .build()

        val navigation = MapboxNavigationApp.current()
        if (navigation == null) {
            result.success(false)
            return
        }

        navigation.requestRoutes(
            options,
            object : NavigationRouterCallback {
                override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                    sendEvent("route_build_cancelled")
                    result.success(false)
                }

                override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
                    sendEvent("route_build_failed")
                    result.success(false)
                }

                override fun onRoutesReady(
                    routes: List<NavigationRoute>,
                    routerOrigin: String
                ) {
                    currentRoutes = routes
                    renderRoute(routes)
                    focusRoute(routes)
                    sendEvent("route_built")
                    result.success(true)
                }
            }
        )
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    private fun startTripSession(
        navigation: com.mapbox.navigation.core.MapboxNavigation,
        simulate: Boolean = false
    ) {
        if (simulate) {
            // Drive the puck along the route from a replayed location stream
            // instead of the device GPS. Without this, `simulateRoute` was a no-op
            // and on an emulator (no real movement) navigation could behave as if
            // the destination had already been reached.
            navigation.startReplayTripSession()
        } else {
            navigation.startTripSession()
        }
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    private fun startSimulation(
        navigation: com.mapbox.navigation.core.MapboxNavigation,
        route: NavigationRoute
    ) {
        val replayer = navigation.mapboxReplayer
        replayer.stop()
        replayer.clearEvents()
        val replayEvents = replayRouteMapper.mapDirectionsRouteGeometry(route.directionsRoute)
        if (replayEvents.isEmpty()) return
        replayer.pushEvents(replayEvents)
        replayer.seekTo(replayEvents.first())
        replayer.play()
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    private fun stopSimulation() {
        MapboxNavigationApp.current()?.mapboxReplayer?.apply {
            stop()
            clearEvents()
        }
    }

    private fun navigationProfile(arguments: Map<*, *>): String {
        return when (arguments["mode"] as? String) {
            "walking" -> DirectionsCriteria.PROFILE_WALKING
            "cycling" -> DirectionsCriteria.PROFILE_CYCLING
            "driving" -> DirectionsCriteria.PROFILE_DRIVING
            else -> DirectionsCriteria.PROFILE_DRIVING_TRAFFIC
        }
    }

    private fun loadInitialStyle() {
        val requestedStyle = options["mapStyleUrlDay"] as? String
        val styleUri = when {
            (options["standardInteractionsEnabled"] as? Boolean) == true -> Style.STANDARD
            !requestedStyle.isNullOrBlank() -> requestedStyle
            else -> Style.STANDARD
        }
        mapView.mapboxMap.loadStyle(styleUri) {
            currentStyle = it
            configureStandardInteractions()
            sendEvent("mapStyleLoaded")
            FlutterMapboxNavigationPlugin.sendEvent("mapStyleLoaded")
        }
    }

    @OptIn(MapboxExperimental::class)
    private fun configureStandardInteractions() {
        if ((options["standardInteractionsEnabled"] as? Boolean) != true) return

        mapView.mapboxMap.addInteraction(
            ClickInteraction.standardPoi { poi, _ ->
                if ((options["hidePoiOnTap"] as? Boolean) == true) {
                    mapView.mapboxMap.setFeatureState(
                        poi,
                        StandardPoiState {
                            hide(true)
                        }
                    )
                }
                sendEvent(
                    "standardPoiTapped",
                    mapOf(
                        "name" to (poi.name ?: ""),
                        "group" to (poi.group ?: "")
                    )
                )
                true
            }
        )

        mapView.mapboxMap.addInteraction(
            ClickInteraction.standardBuildings { building, _ ->
                // Don't visually select/highlight the building
                sendEvent("standardBuildingTapped", emptyMap<String, String>())
                true
            }
        )
    }

    private fun renderRoute(routes: List<NavigationRoute>) {
        val style = currentStyle ?: return
        if (routes.isEmpty()) return
        val navigation = MapboxNavigationApp.current()
        val metadata = navigation?.getAlternativeMetadataFor(routes)
        if (metadata == null) {
            routeLineApi.setNavigationRoutes(routes) { value ->
                routeLineView.renderRouteDrawData(style, value)
            }
        } else {
            routeLineApi.setNavigationRoutes(routes, metadata) { value ->
                routeLineView.renderRouteDrawData(style, value)
            }
        }
    }

    private fun clearRouteLine() {
        val style = currentStyle ?: return
        routeLineApi.clearRouteLine { value ->
            routeLineView.renderClearRouteLineValue(style, value)
        }
    }

    private fun configureViewport() {
        val density = root.resources.displayMetrics.density
        val padding = options["padding"] as? List<*>
        if (padding != null && padding.size == 4) {
            val top = (padding[0] as? Double ?: 0.0) * density
            val left = (padding[1] as? Double ?: 0.0) * density
            val bottom = (padding[2] as? Double ?: 0.0) * density
            val right = (padding[3] as? Double ?: 0.0) * density
            viewportDataSource.followingPadding = EdgeInsets(top, left, bottom, right)
            viewportDataSource.overviewPadding = EdgeInsets(top, left, bottom, right)
        } else {
            viewportDataSource.followingPadding = EdgeInsets(
                130.0 * density,
                0.0,
                220.0 * density,
                0.0
            )
            viewportDataSource.overviewPadding = EdgeInsets(
                130.0 * density,
                24.0 * density,
                220.0 * density,
                24.0 * density
            )
        }
        viewportDataSource.options.followingFrameOptions.defaultPitch =
            options["tilt"] as? Double ?: 58.0
        viewportDataSource.options.followingFrameOptions.maxZoom =
            options["zoom"] as? Double ?: 16.3
    }

    private fun focusRoute(routes: List<NavigationRoute>) {
        val primaryRoute = routes.firstOrNull() ?: return
        viewportDataSource.onRouteChanged(primaryRoute)
        viewportDataSource.evaluate()
        navigationCamera.requestNavigationCameraToOverview()
    }

    private fun registerMapTap() {
        val tapEnabled = options["enableOnMapTapCallback"] as? Boolean ?: true
        if (!tapEnabled) return
        mapView.gestures.addOnMapClickListener { point ->
            val data = mapOf(
                "latitude" to point.latitude().toString(),
                "longitude" to point.longitude().toString()
            )
            sendEvent("on_map_tap", data)
            false
        }
    }

    private fun initializeNavigationSdk(context: Context) {
        // Ensure the shared offline tile store exists, then point routing at it so
        // downloaded regions can serve directions without a network connection.
        com.eopeter.fluttermapboxnavigation.offline.MapboxOfflineManager
            .initialize(context.applicationContext)
        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup {
                val builder = NavigationOptions.Builder(context.applicationContext)
                com.eopeter.fluttermapboxnavigation.offline.MapboxOfflineManager
                    .configureRoutingTiles(builder)
                builder.build()
            }
        }
        MapboxNavigationApp.attach(this)

        val language = options["language"] as? String ?: "en"

        speechApi = MapboxSpeechApi(context, language)
        
        voiceInstructionsPlayer = MapboxVoiceInstructionsPlayer(
            context,
            language
        )

        // Set up location provider & location puck/movement icon
        mapView.location.setLocationProvider(navigationLocationProvider)
        mapView.location.enabled = true
        mapView.location.updateSettings {
            enabled = true
            pulsingEnabled = true
        }

        MapboxNavigationApp.current()
            ?.registerArrivalObserver(arrivalObserver)
        MapboxNavigationApp.current()
            ?.registerLocationObserver(locationObserver)
        MapboxNavigationApp.current()
            ?.registerRouteProgressObserver(routeProgressObserver)
        MapboxNavigationApp.current()
            ?.registerVoiceInstructionsObserver(voiceInstructionObserver)
        MapboxNavigationApp.current()
            ?.registerBannerInstructionsObserver(bannerInstructionObserver)
        MapboxNavigationApp.current()
            ?.registerOffRouteObserver(offRouteObserver)
        MapboxNavigationApp.current()
            ?.registerRoutesObserver(routesObserver)
    }

    private fun sendEvent(eventType: String, data: Any? = null) {
        val payload = if (data == null) {
            mapOf("eventType" to eventType)
        } else {
            mapOf("eventType" to eventType, "data" to data)
        }
        val message = JSONObject(payload).toString()
        // EventChannel sinks must be invoked on the platform (main) thread.
        // Some SDK callbacks (speech generation, router internals) arrive on
        // worker threads and would otherwise terminate the event stream.
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(message)
        } else {
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(message)
            }
        }
    }
}
