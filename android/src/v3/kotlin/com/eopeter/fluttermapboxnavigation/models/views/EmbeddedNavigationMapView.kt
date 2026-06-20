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
import com.mapbox.maps.plugin.animation.MapAnimationOptions
import com.mapbox.maps.CoordinateBounds
import com.mapbox.maps.plugin.scalebar.scalebar
import com.mapbox.maps.plugin.annotation.annotations
import com.mapbox.maps.plugin.annotation.generated.CircleAnnotation
import com.mapbox.maps.plugin.annotation.generated.CircleAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.CircleAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createCircleAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PointAnnotation
import com.mapbox.maps.plugin.annotation.generated.PointAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PointAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createPointAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PolylineAnnotation
import com.mapbox.maps.plugin.annotation.generated.PolylineAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PolylineAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createPolylineAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PolygonAnnotation
import com.mapbox.maps.plugin.annotation.generated.PolygonAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PolygonAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createPolygonAnnotationManager
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
    // Posted speed limit (km/h). iOS populates this during active navigation;
    // Android wiring is pending the exact v3 SpeedData API (tracked follow-up).
    private var currentSpeedLimitKmph: Int? = null
    private var lastLocation: com.mapbox.common.location.Location? = null
    private var currentStyle: Style? = null
    private var voiceInstructionsEnabled = options["voiceInstructionsEnabled"] as? Boolean ?: true

    private var speechApi: MapboxSpeechApi? = null
    private var voiceInstructionsPlayer: MapboxVoiceInstructionsPlayer? = null
    private val replayRouteMapper = ReplayRouteMapper()

    // Dart-driven map markers (drawn independently of the route). We keep the
    // native annotation objects keyed by the caller-provided id so they can be
    // updated/removed individually.
    private var circleAnnotationManager: CircleAnnotationManager? = null
    private var pointAnnotationManager: PointAnnotationManager? = null
    private var polylineAnnotationManager: PolylineAnnotationManager? = null
    private var polygonAnnotationManager: PolygonAnnotationManager? = null
    private val markerCircles = mutableMapOf<String, CircleAnnotation>()
    private val markerLabels = mutableMapOf<String, PointAnnotation>()
    private val userPolylines = mutableMapOf<String, PolylineAnnotation>()
    private val circlePolygons = mutableMapOf<String, PolygonAnnotation>()
    private val circleStrokes = mutableMapOf<String, PolylineAnnotation>()

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
            lastLocation = enhancedLocation
            navigationLocationProvider.changePosition(
                enhancedLocation,
                locationMatcherResult.keyPoints
            )
            viewportDataSource.onLocationChanged(enhancedLocation)
            viewportDataSource.evaluate()
            sendEvent(
                "location_change",
                mapOf(
                    "latitude" to enhancedLocation.latitude,
                    "longitude" to enhancedLocation.longitude,
                    "bearing" to enhancedLocation.bearing,
                    "speed" to enhancedLocation.speed,
                    "speedLimit" to currentSpeedLimitKmph
                )
            )
        }
    }

    private val arrivalObserver = object : ArrivalObserver {
        override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
            hasArrived = true
            sendEvent("on_arrival")
        }

        override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) = Unit

        override fun onWaypointArrival(routeProgress: RouteProgress) {
            sendEvent(
                "waypoint_arrival",
                mapOf("index" to (routeProgress.currentLegProgress?.legIndex ?: 0))
            )
        }
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
        val currentStep = routeProgress.currentLegProgress?.currentStepProgress?.step
        val upcomingStep = routeProgress.currentLegProgress?.upcomingStep
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
                    currentStep?.maneuver()?.instruction() ?: ""
                    ),
                "maneuverType" to (currentStep?.maneuver()?.type() ?: ""),
                "maneuverModifier" to (currentStep?.maneuver()?.modifier() ?: ""),
                "upcomingInstruction" to (
                    upcomingStep?.maneuver()?.instruction() ?: ""
                    ),
                "currentRoadName" to (currentStep?.name() ?: ""),
                "upcomingRoadName" to (upcomingStep?.name() ?: ""),
                "legIndex" to routeProgress.currentLegProgress?.legIndex,
                "stepIndex" to 0,
                "isPrimary" to true,
                "currentSpeed" to currentSpeed,
                "speedLimit" to currentSpeedLimitKmph
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
            "overview" -> {
                navigationCamera.requestNavigationCameraToOverview()
                sendEvent("camera_state_changed", mapOf("state" to "overview"))
                result.success(true)
            }
            "moveCamera" -> {
                moveCamera(call, result)
            }
            "getCurrentLocation" -> {
                val loc = lastLocation
                if (loc == null) {
                    result.success(null)
                } else {
                    result.success(
                        mapOf(
                            "latitude" to loc.latitude,
                            "longitude" to loc.longitude,
                            "bearing" to loc.bearing,
                            "speed" to loc.speed,
                            "speedLimit" to currentSpeedLimitKmph
                        )
                    )
                }
            }
            "getCameraPosition" -> {
                val c = mapView.mapboxMap.cameraState
                result.success(
                    mapOf(
                        "latitude" to c.center.latitude(),
                        "longitude" to c.center.longitude(),
                        "zoom" to c.zoom,
                        "bearing" to c.bearing,
                        "tilt" to c.pitch
                    )
                )
            }
            "fitBounds" -> {
                fitBounds(call, result)
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
            "addMarkers" -> {
                val args = call.arguments as? Map<*, *>
                val markers = args?.get("markers") as? List<*>
                if (markers == null) {
                    result.success(false)
                    return
                }
                addMarkers(markers)
                result.success(true)
            }
            "removeMarker" -> {
                val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                if (id != null) removeMarkerById(id)
                result.success(true)
            }
            "clearMarkers" -> {
                circleAnnotationManager?.deleteAll()
                pointAnnotationManager?.deleteAll()
                markerCircles.clear()
                markerLabels.clear()
                result.success(true)
            }
            "addPolylines" -> {
                val list = (call.arguments as? Map<*, *>)?.get("polylines") as? List<*>
                if (list == null) {
                    result.success(false)
                    return
                }
                addPolylines(list)
                result.success(true)
            }
            "removePolyline" -> {
                val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                if (id != null) {
                    userPolylines.remove(id)?.let { polylineAnnotationManager?.delete(it) }
                }
                result.success(true)
            }
            "clearPolylines" -> {
                userPolylines.values.forEach { polylineAnnotationManager?.delete(it) }
                userPolylines.clear()
                result.success(true)
            }
            "addCircles" -> {
                val list = (call.arguments as? Map<*, *>)?.get("circles") as? List<*>
                if (list == null) {
                    result.success(false)
                    return
                }
                addCircles(list)
                result.success(true)
            }
            "removeCircle" -> {
                val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                if (id != null) removeCircleById(id)
                result.success(true)
            }
            "clearCircles" -> {
                circlePolygons.values.forEach { polygonAnnotationManager?.delete(it) }
                circleStrokes.values.forEach { polylineAnnotationManager?.delete(it) }
                circlePolygons.clear()
                circleStrokes.clear()
                result.success(true)
            }
            "addWayPoints" -> {
                addWayPoints(call, result)
            }
            "selectAlternativeRoute" -> {
                val index = (call.arguments as? Map<*, *>)?.get("index") as? Int ?: 0
                val routes = currentRoutes
                val navigation = MapboxNavigationApp.current()
                if (routes != null && index in routes.indices) {
                    val reordered = routes.toMutableList()
                    reordered.add(0, reordered.removeAt(index))
                    currentRoutes = reordered
                    navigation?.setNavigationRoutes(reordered)
                    renderRoute(reordered)
                    focusRoute(reordered)
                    sendAlternatives(reordered)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureAnnotationManagers() {
        if (circleAnnotationManager == null) {
            circleAnnotationManager = mapView.annotations.createCircleAnnotationManager()
        }
        if (polygonAnnotationManager == null) {
            polygonAnnotationManager = mapView.annotations.createPolygonAnnotationManager()
        }
        if (polylineAnnotationManager == null) {
            polylineAnnotationManager = mapView.annotations.createPolylineAnnotationManager()
        }
        // Create the point manager last so labels/icons draw above the shapes.
        if (pointAnnotationManager == null) {
            pointAnnotationManager = mapView.annotations.createPointAnnotationManager()
        }
    }

    private fun addMarkers(markers: List<*>) {
        ensureAnnotationManagers()
        markers.forEach { raw ->
            val marker = raw as? Map<*, *> ?: return@forEach
            val id = marker["id"] as? String ?: return@forEach
            val lat = marker["latitude"] as? Double ?: return@forEach
            val lng = marker["longitude"] as? Double ?: return@forEach
            val color = marker["color"] as? String ?: "#FF3B30"
            val radius = marker["radius"] as? Double ?: 8.0
            val label = marker["label"] as? String
            val imageBase64 = marker["imageBase64"] as? String

            // Replace any existing marker that uses the same id.
            removeMarkerById(id)

            val point = Point.fromLngLat(lng, lat)
            val bitmap = decodeMarkerBitmap(
                imageBase64,
                marker["imageWidth"] as? Double,
                marker["imageHeight"] as? Double
            )

            if (bitmap != null) {
                // Custom image icon (optionally with a label below it).
                val opts = PointAnnotationOptions()
                    .withPoint(point)
                    .withIconImage(bitmap)
                if (!label.isNullOrEmpty()) {
                    opts.withTextField(label)
                        .withTextOffset(listOf(0.0, 1.4))
                        .withTextColor("#000000")
                        .withTextHaloColor("#FFFFFF")
                        .withTextHaloWidth(1.0)
                }
                pointAnnotationManager?.create(opts)?.let { markerLabels[id] = it }
            } else {
                // Default colored circle, plus an optional text label.
                circleAnnotationManager?.create(
                    CircleAnnotationOptions()
                        .withPoint(point)
                        .withCircleRadius(radius)
                        .withCircleColor(color)
                        .withCircleStrokeColor("#FFFFFF")
                        .withCircleStrokeWidth(2.0)
                )?.let { markerCircles[id] = it }

                if (!label.isNullOrEmpty()) {
                    pointAnnotationManager?.create(
                        PointAnnotationOptions()
                            .withPoint(point)
                            .withTextField(label)
                            .withTextOffset(listOf(0.0, -1.6))
                            .withTextColor("#000000")
                            .withTextHaloColor("#FFFFFF")
                            .withTextHaloWidth(1.0)
                    )?.let { markerLabels[id] = it }
                }
            }
        }
    }

    private fun decodeMarkerBitmap(
        base64: String?,
        width: Double?,
        height: Double?
    ): android.graphics.Bitmap? {
        if (base64.isNullOrEmpty()) return null
        return try {
            val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: return null
            val density = root.resources.displayMetrics.density
            if (width != null && height != null) {
                android.graphics.Bitmap.createScaledBitmap(
                    bitmap,
                    (width * density).toInt(),
                    (height * density).toInt(),
                    true
                )
            } else {
                bitmap
            }
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    private fun addPolylines(list: List<*>) {
        ensureAnnotationManagers()
        list.forEach { raw ->
            val item = raw as? Map<*, *> ?: return@forEach
            val id = item["id"] as? String ?: return@forEach
            val color = item["color"] as? String ?: "#1A73E8"
            val width = item["width"] as? Double ?: 5.0
            val points = (item["points"] as? List<*>)?.mapNotNull { p ->
                val pair = p as? List<*> ?: return@mapNotNull null
                val plat = (pair.getOrNull(0) as? Number)?.toDouble()
                val plng = (pair.getOrNull(1) as? Number)?.toDouble()
                if (plat != null && plng != null) Point.fromLngLat(plng, plat) else null
            } ?: return@forEach
            if (points.size < 2) return@forEach

            userPolylines.remove(id)?.let { polylineAnnotationManager?.delete(it) }
            polylineAnnotationManager?.create(
                PolylineAnnotationOptions()
                    .withPoints(points)
                    .withLineColor(android.graphics.Color.parseColor(color))
                    .withLineWidth(width)
            )?.let { userPolylines[id] = it }
        }
    }

    private fun addCircles(list: List<*>) {
        ensureAnnotationManagers()
        list.forEach { raw ->
            val item = raw as? Map<*, *> ?: return@forEach
            val id = item["id"] as? String ?: return@forEach
            val lat = item["latitude"] as? Double ?: return@forEach
            val lng = item["longitude"] as? Double ?: return@forEach
            val radius = item["radiusMeters"] as? Double ?: return@forEach
            val fill = item["fillColor"] as? String ?: "#331A73E8"
            val stroke = item["strokeColor"] as? String ?: "#1A73E8"
            val strokeWidth = item["strokeWidth"] as? Double ?: 2.0

            removeCircleById(id)
            val ring = circleRing(lat, lng, radius)

            polygonAnnotationManager?.create(
                PolygonAnnotationOptions()
                    .withPoints(listOf(ring))
                    .withFillColor(android.graphics.Color.parseColor(fill))
            )?.let { circlePolygons[id] = it }

            polylineAnnotationManager?.create(
                PolylineAnnotationOptions()
                    .withPoints(ring)
                    .withLineColor(android.graphics.Color.parseColor(stroke))
                    .withLineWidth(strokeWidth)
            )?.let { circleStrokes[id] = it }
        }
    }

    /** Approximate a metric-radius circle as a 64-point geographic ring. */
    private fun circleRing(lat: Double, lng: Double, radiusMeters: Double): List<Point> {
        val points = mutableListOf<Point>()
        val earth = 6378137.0
        val latRad = Math.toRadians(lat)
        val steps = 64
        for (i in 0..steps) {
            val angle = 2.0 * Math.PI * i / steps
            val dx = radiusMeters * Math.cos(angle)
            val dy = radiusMeters * Math.sin(angle)
            val dLat = Math.toDegrees(dy / earth)
            val dLng = Math.toDegrees(dx / (earth * Math.cos(latRad)))
            points.add(Point.fromLngLat(lng + dLng, lat + dLat))
        }
        return points
    }

    private fun removeCircleById(id: String) {
        circlePolygons.remove(id)?.let { polygonAnnotationManager?.delete(it) }
        circleStrokes.remove(id)?.let { polylineAnnotationManager?.delete(it) }
    }

    private fun removeMarkerById(id: String) {
        markerCircles.remove(id)?.let { circleAnnotationManager?.delete(it) }
        markerLabels.remove(id)?.let { pointAnnotationManager?.delete(it) }
    }

    /**
     * Appends one or more intermediate stops to the route currently shown or
     * navigated and recomputes it. The original origin is kept, mirroring the
     * full-screen behaviour. Best effort: needs an existing route to extend.
     */
    private fun addWayPoints(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val waypointsMap = arguments["wayPoints"] as? Map<*, *>
        val navigation = MapboxNavigationApp.current()
        val current = navigation?.getNavigationRoutes()?.firstOrNull()
            ?: currentRoutes?.firstOrNull()
        val routeOptions = current?.directionsRoute?.routeOptions()
        if (navigation == null || routeOptions == null) {
            result.success(false)
            return
        }

        val coordinates = routeOptions.coordinatesList().toMutableList()
        waypointsMap?.values?.forEach {
            val wp = it as? Map<*, *>
            val lat = wp?.get("Latitude") as? Double
            val lng = wp?.get("Longitude") as? Double
            if (lat != null && lng != null) {
                coordinates.add(Point.fromLngLat(lng, lat))
            }
        }

        val newOptions = routeOptions.toBuilder().coordinatesList(coordinates).build()
        navigation.requestRoutes(
            newOptions,
            object : NavigationRouterCallback {
                override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                    result.success(false)
                }

                override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
                    sendEvent("route_build_failed")
                    result.success(false)
                }

                override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                    currentRoutes = routes
                    navigation.setNavigationRoutes(routes)
                    renderRoute(routes)
                    focusRoute(routes)
                    sendEvent("route_built")
                    sendAlternatives(routes)
                    result.success(true)
                }
            }
        )
    }

    private fun moveCamera(call: MethodCall, result: MethodChannel.Result) {
        val a = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val lat = a["latitude"] as? Double
        val lng = a["longitude"] as? Double
        if (lat == null || lng == null) {
            result.success(false)
            return
        }
        // Detach the navigation camera so it stops fighting a manual move.
        navigationCamera.requestNavigationCameraToIdle()
        val builder = CameraOptions.Builder().center(Point.fromLngLat(lng, lat))
        (a["zoom"] as? Double)?.let { builder.zoom(it) }
        (a["bearing"] as? Double)?.let { builder.bearing(it) }
        (a["tilt"] as? Double)?.let { builder.pitch(it) }
        val camera = builder.build()
        if (a["animate"] as? Boolean ?: true) {
            val duration = (a["durationMs"] as? Number)?.toLong() ?: 1000L
            mapView.camera.flyTo(
                camera,
                MapAnimationOptions.Builder().duration(duration).build()
            )
        } else {
            mapView.mapboxMap.setCamera(camera)
        }
        result.success(true)
    }

    private fun fitBounds(call: MethodCall, result: MethodChannel.Result) {
        val a = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val swLat = a["southwestLat"] as? Double
        val swLng = a["southwestLng"] as? Double
        val neLat = a["northeastLat"] as? Double
        val neLng = a["northeastLng"] as? Double
        if (swLat == null || swLng == null || neLat == null || neLng == null) {
            result.success(false)
            return
        }
        navigationCamera.requestNavigationCameraToIdle()
        val density = root.resources.displayMetrics.density
        val pad = ((a["padding"] as? Number)?.toDouble() ?: 40.0) * density
        val bounds = CoordinateBounds(
            Point.fromLngLat(swLng, swLat),
            Point.fromLngLat(neLng, neLat)
        )
        val camera = mapView.mapboxMap.cameraForCoordinateBounds(
            bounds,
            EdgeInsets(pad, pad, pad, pad),
            null,
            null
        )
        if (a["animate"] as? Boolean ?: true) {
            mapView.camera.flyTo(
                camera,
                MapAnimationOptions.Builder().duration(1000L).build()
            )
        } else {
            mapView.mapboxMap.setCamera(camera)
        }
        result.success(true)
    }

    private fun sendAlternatives(routes: List<NavigationRoute>) {
        if (routes.isEmpty()) return
        val list = routes.mapIndexed { index, route ->
            mapOf(
                "index" to index,
                "distance" to route.directionsRoute.distance(),
                "duration" to route.directionsRoute.duration(),
                "isPrimary" to (index == 0),
                "geometry" to routeGeometry(route)
            )
        }
        sendEvent("alternative_routes", list)
    }

    /** Decode a route's polyline into a list of [lat, lng] pairs for Dart. */
    private fun routeGeometry(route: NavigationRoute): List<List<Double>> {
        val geometry = route.directionsRoute.geometry() ?: return emptyList()
        return try {
            com.mapbox.geojson.LineString.fromPolyline(geometry, 6)
                .coordinates()
                .map { listOf(it.latitude(), it.longitude()) }
        } catch (e: RuntimeException) {
            emptyList()
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
        // Road classes to avoid (toll, motorway, ferry, ...). Accept the value
        // either on the per-call arguments or the view-level options.
        val excludeList = (arguments["exclude"] as? List<*>
            ?: this.options["exclude"] as? List<*>)
            ?.mapNotNull { it as? String }
            ?.filter { it.isNotBlank() }

        val options = RouteOptions.builder()
            .applyDefaultNavigationOptions(navigationProfile(arguments))
            .applyLanguageAndVoiceUnitOptions(activity)
            .apply {
                if (!routeLanguage.isNullOrBlank()) language(routeLanguage)
                if (!routeUnits.isNullOrBlank()) voiceUnits(routeUnits)
                if (!excludeList.isNullOrEmpty()) excludeList(excludeList)
            }
            .coordinatesList(waypoints)
            .alternatives(arguments["alternatives"] as? Boolean ?: false)
            .enableRefresh(
                arguments["enableRefresh"] as? Boolean
                    ?: this.options["enableRefresh"] as? Boolean
                    ?: false
            )
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
                    sendAlternatives(routes)
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
