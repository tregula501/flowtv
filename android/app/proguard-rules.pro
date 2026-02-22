# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# media_kit (libmpv)
-keep class com.alexmercerind.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }

# Google Cast
-keep class com.google.android.gms.cast.** { *; }
-keep class com.felnanuke.google_cast.** { *; }
-keep class androidx.mediarouter.** { *; }

# Drift (SQLite)
-keep class org.sqlite.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Play Core (referenced by Flutter engine, not used directly)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Keep annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
