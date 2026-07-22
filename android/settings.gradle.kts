pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // v278 — Android Gradle Plugin bumped 8.7.3 → 8.9.1. Six
    // transitive androidx deps (browser:1.9.0, activity:1.12.4,
    // activity-ktx:1.12.4, navigationevent-android:1.0.2,
    // core:1.18.0, core-ktx:1.18.0) require AGP 8.9.1+ as of
    // their latest releases, so the AAR metadata check fails on
    // ':app:checkReleaseAarMetadata' until the plugin catches up.
    // Gradle wrapper is already on 8.12 which supports AGP 8.9.x,
    // so this is a single-line bump with no other changes needed.
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
