package com.eopeter.fluttermapboxnavigation

import com.mapbox.common.MapboxOptions

/**
 * Hands the public token the Dart side passed in `MapBoxOptions.accessToken`
 * to the native Mapbox SDKs.
 *
 * Without this the Maps renderer and the Navigation router only ever read the
 * host app's `mapbox_access_token` string resource, which is fixed at build
 * time. A build made with a missing or placeholder token then ships a map that
 * draws nothing and a router that refuses every route, even though the app
 * itself holds a working token (from its server config or build defines).
 *
 * The token is process-global, so this must run before the first `MapView` is
 * created and before the first route request.
 */
internal object MapboxAccessToken {
    fun applyFrom(options: Map<*, *>?) {
        val token = (options?.get("accessToken") as? String)?.trim() ?: return
        if (!isPublicToken(token)) return
        // Assign without reading first: the getter falls back to the string
        // resource and can throw when that resource is empty.
        MapboxOptions.accessToken = token
    }

    /**
     * A real public token is `pk.` followed by a base64 JSON payload, which
     * always starts `eyJ`. Anything else (a `pk.your_…` placeholder, a secret
     * `sk.` token) would only replace one broken token with another.
     */
    fun isPublicToken(token: String): Boolean = token.startsWith("pk.eyJ")
}
