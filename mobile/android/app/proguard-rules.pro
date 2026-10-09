# Applied automatically by Flutter to release builds when code shrinking is on
# (see `shrink` in ../gradle.properties).

# ── ML Kit face detection ─────────────────────────────────────────────────────
# ML Kit looks up its internal components at runtime (registrar classes named
# in its AndroidManifest, JNI callbacks from the bundled detector). R8 cannot
# see those uses and strips them, and release builds then fail inside
# InputImage.fromByteArray with
#   "NullPointerException: ... Object.getClass() on a null object reference".
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.odml.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**

# ── LiteRT / TensorFlow Lite (MobileFaceNet) ──────────────────────────────────
-keep class org.tensorflow.lite.** { *; }
-keep class com.google.ai.edge.litert.** { *; }
-dontwarn org.tensorflow.lite.**
-dontwarn com.google.ai.edge.litert.**
