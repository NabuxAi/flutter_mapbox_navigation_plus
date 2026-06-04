package com.eopeter.fluttermapboxnavigation

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
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
