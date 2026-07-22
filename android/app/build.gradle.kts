
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.debloatos.app"
    compileSdk = flutter.compileSdkVersion
    // Pinned to an explicit NDK so builds are deterministic across machines.
    ndkVersion = "27.0.12077973"

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
        applicationId = "com.debloatos.app"

        // ML Kit Face Mesh requires Android 6.0+ (API 23); floor kept at
        // 24 for a consistent camera/detector baseline.
        // Source: https://developers.google.com/ml-kit/vision/face-mesh-detection/android
        minSdk = 24
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

    // Upload-key signing for Debloat OS. Generate a FRESH keystore for
    // this app (do NOT reuse another app's key):
    //   keytool -genkey -v -keystore upload-keystore.jks \
    //     -keyalg RSA -keysize 2048 -validity 10000 -alias debloatos
    // Drop it at android/app/upload-keystore.jks; creds come from env
    // (CI) or the values you set here. Release builds fall back to the
    // debug key while no keystore is present so local `flutter build`
    // still works.
    val uploadKeystore = file("upload-keystore.jks")
    signingConfigs {
        create("release") {
            if (uploadKeystore.exists()) {
                storeFile = uploadKeystore
                storePassword = System.getenv("STORE_PASSWORD") ?: ""
                keyAlias = System.getenv("KEY_ALIAS") ?: "debloatos"
                keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (uploadKeystore.exists())
                signingConfigs.getByName("release")
            else signingConfigs.getByName("debug")

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
