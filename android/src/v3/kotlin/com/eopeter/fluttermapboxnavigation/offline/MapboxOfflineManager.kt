package com.eopeter.fluttermapboxnavigation.offline

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.eopeter.fluttermapboxnavigation.FlutterMapboxNavigationPlugin
import com.mapbox.common.NetworkRestriction
import com.mapbox.common.TileRegionLoadOptions
import com.mapbox.common.TileStore
import com.mapbox.geojson.Point
import com.mapbox.geojson.Polygon
import com.mapbox.maps.MapboxMapsOptions
import com.mapbox.maps.OfflineManager
import com.mapbox.maps.Style
import com.mapbox.maps.StylePackLoadOptions
import com.mapbox.maps.TileStoreUsageMode
import com.mapbox.maps.TilesetDescriptorOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.options.RoutingTilesOptions
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import io.flutter.plugin.common.MethodChannel

/**
 * Handles full offline support (maps + routing) for the v3 implementation.
 *
 * A single shared [TileStore] is wired into both the Maps renderer (via the
 * global [MapboxMapsOptions]) and the Navigation SDK (via [RoutingTilesOptions]),
 * so a downloaded region serves both map tiles and routing tiles. Callers select
 * the region as an arbitrary polygon, supplied from Dart.
 *
 * All Mapbox offline API usage is intentionally confined to this file so the rest
 * of the plugin only depends on these stable method signatures.
 */
object MapboxOfflineManager {

    private var tileStore: TileStore? = null
    private var offlineManager: OfflineManager? = null

    /**
     * Create the shared tile store and route both Maps and downloaded data
     * through it. Safe to call multiple times. Must run before the first MapView
     * is created so the renderer picks up the store.
     */
    fun initialize(context: Context) {
        if (tileStore != null) return
        val store = TileStore.create()
        tileStore = store
        MapboxMapsOptions.tileStore = store
        // READ_ONLY, not READ_AND_UPDATE.
        //
        // READ_AND_UPDATE makes the renderer ask the network for whole tile
        // *packs* rather than individual tiles, and consult only the tile store
        // for what it already has. Anywhere the user has not downloaded a
        // region, the map is therefore blank — and because the same store backs
        // the routing tiles, a route through that area cannot be built either.
        // Enabling offline support at the start of every navigation session
        // (which is what the app does) turned that into: leave the one
        // downloaded city and the map is empty and every route fails.
        //
        // READ_ONLY reads downloaded packs where they exist and falls back to
        // ordinary per-tile network requests everywhere else, which is the
        // hybrid behaviour offline support was supposed to add.
        MapboxMapsOptions.tileStoreUsageMode = TileStoreUsageMode.READ_ONLY
        offlineManager = OfflineManager()
    }

    /** Point the Navigation SDK's routing tiles at the shared store. */
    fun configureRoutingTiles(builder: NavigationOptions.Builder) {
        val store = tileStore ?: return
        builder.routingTilesOptions(
            RoutingTilesOptions.Builder().tileStore(store).build()
        )
    }

    /**
     * Download a region (map + routing tiles) covering the supplied polygon.
     *
     * @param coordinates outer ring as a list of [longitude, latitude] pairs.
     */
    fun downloadRegion(
        regionId: String,
        coordinates: List<List<Double>>,
        minZoom: Int,
        maxZoom: Int,
        styleUrl: String?
    ) {
        val store = tileStore
        val offline = offlineManager
        if (store == null || offline == null) {
            emit("offline_region_error", mapOf("id" to regionId, "message" to "Offline manager not initialized"))
            return
        }
        if (coordinates.size < 3) {
            emit("offline_region_error", mapOf("id" to regionId, "message" to "A polygon needs at least 3 points"))
            return
        }

        val styleUri = if (styleUrl.isNullOrBlank()) Style.STANDARD else styleUrl
        val ring = coordinates.map { Point.fromLngLat(it[0], it[1]) }
        val polygon = Polygon.fromLngLats(listOf(ring))

        val descriptors = mutableListOf(
            offline.createTilesetDescriptor(
                TilesetDescriptorOptions.Builder()
                    .styleURI(styleUri)
                    .minZoom(minZoom.toByte())
                    .maxZoom(maxZoom.toByte())
                    .build()
            )
        )
        // Routing tiles for the same area, so directions work offline too.
        MapboxNavigationApp.current()?.tilesetDescriptorFactory?.getLatest()?.let {
            descriptors.add(it)
        }

        // Style pack lets the map render fully offline (fonts, sprites, sources).
        offline.loadStylePack(
            styleUri,
            StylePackLoadOptions.Builder().build(),
            { _ -> },
            { _ -> }
        )

        val loadOptions = TileRegionLoadOptions.Builder()
            .geometry(polygon)
            .descriptors(descriptors)
            .acceptExpired(true)
            .networkRestriction(NetworkRestriction.NONE)
            .build()

        store.loadTileRegion(
            regionId,
            loadOptions,
            { progress ->
                val required = progress.requiredResourceCount
                val pct = if (required > 0) {
                    progress.completedResourceCount.toDouble() / required.toDouble() * 100.0
                } else {
                    0.0
                }
                emit(
                    "offline_region_progress",
                    mapOf(
                        "id" to regionId,
                        "progress" to pct,
                        "completedResourceCount" to progress.completedResourceCount,
                        "requiredResourceCount" to required
                    )
                )
            },
            { expected ->
                if (expected.isValue) {
                    emit("offline_region_complete", mapOf("id" to regionId))
                } else {
                    emit(
                        "offline_region_error",
                        mapOf("id" to regionId, "message" to (expected.error?.message ?: "unknown error"))
                    )
                }
            }
        )
    }

    /** Delete a previously downloaded region. */
    fun removeRegion(regionId: String) {
        val store = tileStore ?: return
        store.removeTileRegion(regionId)
        emit("offline_region_removed", mapOf("id" to regionId))
    }

    /** Return the ids of all downloaded regions to the Flutter caller. */
    fun listRegions(result: MethodChannel.Result) {
        val store = tileStore
        if (store == null) {
            result.success(emptyList<String>())
            return
        }
        store.getAllTileRegions { expected ->
            val ids = if (expected.isValue) {
                expected.value?.map { it.id } ?: emptyList()
            } else {
                emptyList()
            }
            // TileStore callbacks arrive on a worker thread; channel results must
            // be delivered on the platform (main) thread.
            Handler(Looper.getMainLooper()).post { result.success(ids) }
        }
    }

    private fun emit(eventType: String, data: Map<String, Any?>) {
        FlutterMapboxNavigationPlugin.sendEvent(eventType, data)
    }
}
