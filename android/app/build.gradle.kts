import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Console upload-key fingerprints loaded from play-fingerprints.properties
// — the values that must match the keystore at upload-keystore.jks for Play
// Store to accept the AAB. The Verify-keystore CI step reads these and
// fails the build if the keystore in the repo doesn't match, so a
// wrong-key build never gets shipped past CI.
val playFingerprintsFile = rootProject.file("app/play-fingerprints.properties")
val playFingerprints = Properties().apply {
    if (playFingerprintsFile.exists()) {
        FileInputStream(playFingerprintsFile).use { load(it) }
    }
}
val playUploadKeySha1   = playFingerprints.getProperty("play.upload.key.sha1",   "")
val playUploadKeySha256 = playFingerprints.getProperty("play.upload.key.sha256", "")

android {
    namespace = "com.mirrorly.mirrorly"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Core library desugaring is required by `flutter_local_notifications`
        // (and any plugin targeting java.time on pre-API-26 devices). Without
        // this, `flutter build apk --release` fails on checkReleaseAarMetadata:
        //   ":flutter_local_notifications requires core library desugaring".
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.mirrorly.mirrorly"

        // Bake the registered Play Console fingerprints into BuildConfig
        // so any in-app integrity check or asset_links logic can read
        // them at runtime without re-parsing the properties file.
        buildConfigField("String", "PLAY_UPLOAD_KEY_SHA1",   "\"$playUploadKeySha1\"")
        buildConfigField("String", "PLAY_UPLOAD_KEY_SHA256", "\"$playUploadKeySha256\"")
        // ML Kit Face Mesh requires Android 6.0+ (API 23). Below that the
        // detector loads but silently returns empty meshes — which was our
        // exact Android silent-failure bug.
        // Source: https://developers.google.com/ml-kit/vision/face-mesh-detection/android
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ML Kit does NOT support 32-bit ARM (armv7). Restrict to the ABIs
        // that ship working ML Kit native libraries — arm64 covers modern
        // phones, x86_64 covers emulators.
        // Source: https://developers.google.com/ml-kit/known-issues
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // Upload-key signing config consumed by the `flutter-aab-final`
    // workflow. Creds read from env first (how the GitHub Actions job
    // sets them in the "Verify keystore" step), falling back to the
    // literal workflow defaults so a local `flutter build appbundle
    // --release` works for anyone who already has the .jks dropped in.
    //
    // The keystore file itself lives at android/app/upload-keystore.jks.
    // SHA-1 fingerprint (registered with Play Console):
    //   C2:27:D7:BE:A2:38:70:40:16:6A:E3:D9:BD:23:39:8D:60:DC:08:DE
    // SHA-256:
    //   76:E1:49:7A:35:36:DD:9A:02:8C:DB:46:5F:F8:D2:38:18:C0:FC:40:A2:55:53:C5:C7:AB:CF:2B:A7:5C:BD:ED
    signingConfigs {
        create("release") {
            storeFile = file("upload-keystore.jks")
            storePassword = System.getenv("STORE_PASSWORD") ?: "skeletalpt123"
            keyAlias = System.getenv("KEY_ALIAS") ?: "skeletalpt"
            keyPassword = System.getenv("KEY_PASSWORD") ?: "skeletalpt123"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")

            // ML Kit classes are reached via reflection inside the detector
            // SDK. Without keep rules, R8 silently strips them and the
            // detector emits empty lists. See proguard-rules.pro.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required for `isCoreLibraryDesugaringEnabled = true` above.
    // Version 2.0.4+ is the one flutter_local_notifications documents.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
