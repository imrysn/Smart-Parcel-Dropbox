# Flutter ProGuard/R8 Rules for Smart Parcel Dropbox

# Fix for androidx.window missing classes
-keep class androidx.window.extensions.** { *; }
-keep class androidx.window.sidecar.** { *; }
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Common R8 rules for Flutter plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.editing.** { *; }

# Google Sign-In & Play Services
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**

# Handle missing window classes
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Broad ignore for common R8 false positives
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.**
-dontwarn androidx.**
-dontwarn android.**

# Google ML Kit - Text Recognition
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.ml.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.android.gms.vision.** { *; }
