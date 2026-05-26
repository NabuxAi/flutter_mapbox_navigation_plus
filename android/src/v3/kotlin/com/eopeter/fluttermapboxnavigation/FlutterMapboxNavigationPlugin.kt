package com.eopeter.fluttermapboxnavigation

import android.app.Activity
import android.content.Context
import android.os.Build
import com.eopeter.fluttermapboxnavigation.factory.EmbeddedNavigationViewFactory
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
            "startFreeDrive",
            "startNavigation",
            "addWayPoints" -> {
                result.error(
                    "MAPBOX_NAVIGATION_V3_EMBEDDED_ONLY",
                    "The v3 fork supports embedded navigation first.",
                    null
                )
            }
            "enableOfflineRouting" -> {
                result.error("TODO", "Offline routing is not implemented yet.", null)
            }
            else -> result.notImplemented()
        }
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
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        val registry = platformViewRegistry
        val messenger = binaryMessenger
        if (registry != null && messenger != null) {
            registry.registerViewFactory(
                viewId,
                EmbeddedNavigationViewFactory(messenger, binding.activity)
            )
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
            eventSink?.success(JSONObject(payload).toString())
        }
    }
}
