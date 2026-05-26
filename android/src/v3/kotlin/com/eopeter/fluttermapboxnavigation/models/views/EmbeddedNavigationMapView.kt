package com.eopeter.fluttermapboxnavigation.models.views

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.FrameLayout
import androidx.lifecycle.LifecycleOwner
import com.eopeter.fluttermapboxnavigation.FlutterMapboxNavigationPlugin
import com.mapbox.api.directions.v5.DirectionsCriteria
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.api.directions.v5.models.BannerInstructions
import com.mapbox.geojson.Point
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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject
import java.util.Locale

class EmbeddedNavigationMapView(
    context: Context,
    private val activity: Activity,
    messenger: BinaryMessenger,
    viewId: Int,
    private val args: Any?
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val root = FrameLayout(context)
    private val mapView = MapView(context)
    private val channel = MethodChannel(messenger, "flutter_mapbox_navigation/$viewId")
    private val events = EventChannel(messenger, "flutter_mapbox_navigation/$viewId/events")
    private val options = (args as? Map<*, *>) ?: emptyMap<String, Any>()
    private val viewportDataSource = MapboxNavigationViewportDataSource(mapView.mapboxMap)
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
    private var currentStyle: Style? = null
    private var voiceInstructionsEnabled = options["voiceInstructionsEnabled"] as? Boolean ?: true

    private var speechApi: MapboxSpeechApi? = null
    private var voiceInstructionsPlayer: MapboxVoiceInstructionsPlayer? = null

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
            viewportDataSource.onLocationChanged(locationMatcherResult.enhancedLocation)
            viewportDataSource.evaluate()
        }
    }

    private val arrivalObserver = object : ArrivalObserver {
        override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
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
                "arrived" to false,
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
                "isPrimary" to true
            )
        )
    }

    init {
        root.addView(mapView)
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
        initializeNavigationSdk(context)
        loadInitialStyle()
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
        MapboxNavigationApp.current()?.stopTripSession()
        speechApi?.cancel()
        voiceInstructionsPlayer?.shutdown()
        routeLineApi.cancel()
        routeLineView.cancel()
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
        mapView.onDestroy()
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
                    navigation.setNavigationRoutes(routes)
                    startTripSession(navigation)
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
                result.success(enabled)
            }
            else -> result.notImplemented()
        }
    }

    private fun buildRoute(call: MethodCall, result: MethodChannel.Result) {
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

        val options = RouteOptions.builder()
            .applyDefaultNavigationOptions(navigationProfile(arguments))
            .applyLanguageAndVoiceUnitOptions(activity)
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

    private fun startTripSession(
        navigation: com.mapbox.navigation.core.MapboxNavigation
    ) {
        navigation.startTripSession()
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
                mapView.mapboxMap.setFeatureState(
                    building,
                    StandardBuildingsState {
                        select(true)
                    }
                )
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
        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup {
                NavigationOptions.Builder(context.applicationContext).build()
            }
        }
        (activity as? LifecycleOwner)?.let { owner ->
            MapboxNavigationApp.attach(owner)
        }

        val language = options["language"] as? String ?: "en"

        speechApi = MapboxSpeechApi(context, language)
        
        voiceInstructionsPlayer = MapboxVoiceInstructionsPlayer(
            context,
            language
        )

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
        eventSink?.success(JSONObject(payload).toString())
    }
}
