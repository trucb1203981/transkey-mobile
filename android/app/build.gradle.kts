import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.transkey.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.transkey.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Drop x86_64 to satisfy Play 16 KB page size check. The
        // tflite_flutter prebuilt libtensorflowlite_*_jni.so for x86_64
        // ships with 4 KB ELF alignment (0x1000), which fails Play's
        // "Recompile your app with 16 KB native library alignment"
        // requirement. arm64-v8a + armeabi-v7a cover ~99% of mobile
        // devices; x86_64 is mostly emulators / a handful of Intel
        // Chromebooks. Drop until tflite_flutter ships a 16 KB-aligned
        // x86_64 build.
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a"))
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                // Resolve relative to android/ (rootProject), not android/app/ —
                // matches the path written in key.properties (e.g. "app/upload-keystore.jks").
                storeFile = rootProject.file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback to debug signing when key.properties is missing
                // (e.g., fresh clone) so `flutter run --release` still works.
                signingConfigs.getByName("debug")
            }
        }
    }

    // Required for Google Play 16 KB page size compliance (Nov 2025+).
    // Tells AGP to package .so files uncompressed and 16 KB-aligned in the
    // APK so the loader can mmap them on devices with 16 KB pages
    // (e.g. Android 15 on Pixel 8 / arm64). Without this, Play Console
    // rejects the AAB with "Your app does not support 16 KB memory page sizes".
    //
    // ALSO excludes x86_64 native libs because tflite_flutter ships
    // libtensorflowlite_*_jni.so for x86_64 with 4 KB ELF alignment
    // (p_align = 0x1000), which fails Play's 16 KB check even with
    // useLegacyPackaging = false. Flutter's --target-platform drops
    // libflutter.so / libapp.so for x86_64 but does NOT drop bundled
    // Android plugin libs; AGP defaultConfig.ndk.abiFilters is also
    // ignored when Flutter manages the build. This exclude path is the
    // belt-and-suspenders fix.
    packaging {
        jniLibs {
            useLegacyPackaging = false
            excludes += setOf("**/x86_64/**", "**/x86/**")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ML Kit on-device text recognition for the bubble "Scan screen" / OCR
    // flow. Latin is required; the CJK + Korean modules let us read sources
    // the user is most likely to point the lens at (manga, JP/KR apps,
    // mainland Chinese sites). Each module ships its own offline model and
    // adds ~3 MB to the APK — drop any if footprint becomes a concern.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")

    // EXIF-aware decoding for BgColorSampler. BitmapFactory ignores the
    // JPEG orientation tag, so a capture that carries an unbaked EXIF
    // rotation would be read in the WRONG orientation - the sampler
    // would then grab pixels at coordinates that don't line up with
    // ML Kit's bounding boxes (which are reported in the EXIF-applied
    // space Flutter renders in). ExifInterface lets us match that space.
    implementation("androidx.exifinterface:exifinterface:1.4.1")

    // JVM unit tests for the pure-Kotlin input-method logic (TelexProcessor
    // and the other composers have no Android deps, so they run on the plain
    // JVM - fast, no device). Run: ./gradlew :app:testDebugUnitTest
    testImplementation("junit:junit:4.13.2")
}
