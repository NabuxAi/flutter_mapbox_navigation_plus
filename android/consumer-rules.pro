# Mapbox's Directions models reference compile-time-only AutoValue/ErrorProne
# annotations. R8 flags these as "missing classes" in release builds of apps that
# enable minification. They are safe to ignore.
-dontwarn com.google.auto.value.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# Keep Mapbox Directions model classes (serialized via Gson/AutoValue).
-keep class com.mapbox.api.directions.v5.models.** { *; }
-keep class com.mapbox.api.directions.v5.** { *; }
