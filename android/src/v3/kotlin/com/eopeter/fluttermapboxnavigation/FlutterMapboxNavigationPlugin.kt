package com.eopeter.fluttermapboxnavigation

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.eopeter.fluttermapboxnavigation.activity.NavigationActivity
import com.eopeter.fluttermapboxnavigation.factory.EmbeddedNavigationViewFactory
import com.eopeter.fluttermapboxnavigation.offline.MapboxOfflineManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewRegistry
import org.json.JSONObject

class FlutterMapboxNavigationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var currentActivity: Activity? = null
    private var viewFactory: EmbeddedNavigationViewFactory? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        channel = MethodChannel(messenger, "flutter_mapbox_navigation")
        channel.setMethodCallHandler(this)
        events = EventChannel(messenger, "flutter_mapbox_navigation/events")
        events.setStreamHandler(this)
        platformViewRegistry = binding.platformViewRegistry
        binaryMessenger = messenger
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "getDistanceRemaining" -> result.success(distanceRemaining)
            "getDurationRemaining" -> result.success(durationRemaining)
            "finishNavigation" -> {
                sendEvent("navigation_cancelled")
                result.success(true)
            }
            "startFreeDrive" -> {
                val act = currentActivity
                if (act == null) {
                    result.error("NO_CONTEXT", "No activity context available.", null)
                    return
                }
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val intent = Intent(act, NavigationActivity::class.java)
                intent.putExtra("isFreeDrive", true)
                putNavExtras(intent, args)
                act.startActivity(intent)
                result.success(true)
            }
            "startNavigation" -> {
                val act = currentActivity
                if (act == null) {
                    result.error("NO_CONTEXT", "No activity context available.", null)
                    return
                }
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val (lats, lngs) = waypointArrays(args)
                if (lats.size < 2) {
                    result.error("INVALID_WAYPOINTS", "Need at least 2 waypoints.", null)
                    return
                }
                val intent = Intent(act, NavigationActivity::class.java)
                intent.putExtra("lats", lats)
                intent.putExtra("lngs", lngs)
                intent.putExtra("isFreeDrive", false)
                putNavExtras(intent, args)
                act.startActivity(intent)
                result.success(true)
            }
            "addWayPoints" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val (lats, lngs) = waypointArrays(args)
                NavigationActivity.active?.addWaypoints(lats, lngs)
                result.success(true)
            }
            "enableOfflineRouting" -> {
                val ctx = currentActivity?.applicationContext
                if (ctx == null) {
                    result.error("NO_CONTEXT", "No activity context available.", null)
                } else {
                    MapboxOfflineManager.initialize(ctx)
                    result.success(true)
                }
            }
            "downloadOfflineRegion" -> {
                val ctx = currentActivity?.applicationContext
                if (ctx == null) {
                    result.error("NO_CONTEXT", "No activity context available.", null)
                    return
                }
                MapboxOfflineManager.initialize(ctx)
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val id = args["id"] as? String ?: "default-region"
                val minZoom = (args["minZoom"] as? Number)?.toInt() ?: 0
                val maxZoom = (args["maxZoom"] as? Number)?.toInt() ?: 16
                val styleUrl = args["styleUrl"] as? String
                @Suppress("UNCHECKED_CAST")
                val coordinates =
                    (args["coordinates"] as? List<List<Double>>) ?: emptyList()
                MapboxOfflineManager.downloadRegion(id, coordinates, minZoom, maxZoom, styleUrl)
                result.success(true)
            }
            "removeOfflineRegion" -> {
                val ctx = currentActivity?.applicationContext
                if (ctx != null) MapboxOfflineManager.initialize(ctx)
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val id = args["id"] as? String
                if (id == null) {
                    result.error("NO_ID", "An offline region id is required.", null)
                } else {
                    MapboxOfflineManager.removeRegion(id)
                    result.success(true)
                }
            }
            "getOfflineRegions" -> {
                val ctx = currentActivity?.applicationContext
                if (ctx != null) MapboxOfflineManager.initialize(ctx)
                MapboxOfflineManager.listRegions(result)
            }
            else -> result.notImplemented()
        }
    }

    /** Extract waypoint latitudes/longitudes from the Flutter `wayPoints` map. */
    private fun waypointArrays(args: Map<*, *>): Pair<DoubleArray, DoubleArray> {
        val wayPoints = args["wayPoints"] as? Map<*, *>
        val lats = ArrayList<Double>()
        val lngs = ArrayList<Double>()
        wayPoints?.values?.forEach {
            val wp = it as? Map<*, *>
            val lat = wp?.get("Latitude") as? Double
            val lng = wp?.get("Longitude") as? Double
            if (lat != null && lng != null) {
                lats.add(lat)
                lngs.add(lng)
            }
        }
        return lats.toDoubleArray() to lngs.toDoubleArray()
    }

    /** Copy the common navigation options onto the full-screen activity intent. */
    private fun putNavExtras(intent: Intent, args: Map<*, *>) {
        intent.putExtra("simulateRoute", args["simulateRoute"] as? Boolean ?: false)
        intent.putExtra("alternatives", args["alternatives"] as? Boolean ?: false)
        intent.putExtra("enableRefresh", args["enableRefresh"] as? Boolean ?: false)
        intent.putExtra("voiceEnabled", args["voiceInstructionsEnabled"] as? Boolean ?: true)
        (args["mode"] as? String)?.let { intent.putExtra("mode", it) }
        (args["language"] as? String)?.let { intent.putExtra("language", it) }
        (args["units"] as? String)?.let { intent.putExtra("units", it) }
        (args["mapStyleUrlDay"] as? String)?.let { intent.putExtra("mapStyleUrlDay", it) }
        (args["tilt"] as? Double)?.let { intent.putExtra("tilt", it) }
        (args["zoom"] as? Double)?.let { intent.putExtra("zoom", it) }
        (args["initialLatitude"] as? Double)?.let { intent.putExtra("initialLatitude", it) }
        (args["initialLongitude"] as? Double)?.let { intent.putExtra("initialLongitude", it) }
        (args["exclude"] as? List<*>)
            ?.mapNotNull { it as? String }
            ?.filter { it.isNotBlank() }
            ?.takeIf { it.isNotEmpty() }
            ?.let { intent.putExtra("exclude", it.toTypedArray()) }
    }

    override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(args: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        currentActivity = null
        viewFactory = null
        // Clear engine-scoped statics so a destroyed engine's messenger,
        // registry and sink are never reused (and can be re-registered by the
        // next engine instance).
        eventSink = null
        platformViewRegistry = null
        binaryMessenger = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        // Set up the shared tile store before any MapView is created so both the
        // map renderer and routing can read from downloaded offline regions.
        MapboxOfflineManager.initialize(binding.activity.applicationContext)

        // A factory may only be registered once per engine; a second call
        // throws IllegalStateException (this used to crash on rotation/theme
        // changes). Re-attach just refreshes the activity reference instead.
        val existing = viewFactory
        if (existing != null) {
            existing.activity = binding.activity
            return
        }

        val registry = platformViewRegistry
        val messenger = binaryMessenger
        if (registry != null && messenger != null) {
            val factory = EmbeddedNavigationViewFactory(messenger, binding.activity)
            viewFactory = factory
            registry.registerViewFactory(viewId, factory)
        }
    }

    override fun onDetachedFromActivity() {
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        currentActivity = null
    }

    companion object {
        var eventSink: EventChannel.EventSink? = null
        var distanceRemaining: Float? = null
        var durationRemaining: Double? = null
        var platformViewRegistry: PlatformViewRegistry? = null
        var binaryMessenger: BinaryMessenger? = null
        var viewId = "FlutterMapboxNavigationView"

        fun sendEvent(eventType: String, data: Any? = null) {
            val payload = if (data == null) {
                mapOf("eventType" to eventType)
            } else {
                mapOf("eventType" to eventType, "data" to data)
            }
            val message = JSONObject(payload).toString()
            // EventChannel sinks must be invoked on the platform (main) thread;
            // callers may invoke this from SDK worker threads.
            if (Looper.myLooper() == Looper.getMainLooper()) {
                eventSink?.success(message)
            } else {
                Handler(Looper.getMainLooper()).post {
                    eventSink?.success(message)
                }
            }
        }
    }
}
