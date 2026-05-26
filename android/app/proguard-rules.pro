# ML Kit text recognition — referenced via reflection by google_mlkit_text_recognition Flutter plugin.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.latin.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }

# tflite_flutter — the GPU delegate is an optional add-on (separate
# package tflite_flutter_helper) but R8 sees the GpuDelegate references
# in the base jar and fails the release build if those classes aren't
# kept. We're CPU-only (DBNet ~200 ms on CPU is fine), so we tell R8 the
# GPU classes don't exist instead of pulling in the extra Maven dep.
-dontwarn org.tensorflow.lite.gpu.**
-keep class org.tensorflow.lite.** { *; }
