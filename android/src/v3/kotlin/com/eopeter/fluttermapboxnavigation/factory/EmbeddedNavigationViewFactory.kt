package com.eopeter.fluttermapboxnavigation.factory

import android.app.Activity
import android.content.Context
import com.eopeter.fluttermapboxnavigation.models.views.EmbeddedNavigationMapView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class EmbeddedNavigationViewFactory(
    private val messenger: BinaryMessenger,
    private val activity: Activity
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return EmbeddedNavigationMapView(context, activity, messenger, viewId, args)
    }
}
