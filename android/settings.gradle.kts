pluginManagement {
    val flutterSdkPath =
        run {
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
    // 8.13.x, and the floor is not ours: `share_plus` 12 and `device_info_plus`
    // 12 each declare "Android Gradle Plugin >=8.12.1", and share_plus 12 is
    // already here - so 8.11.1 was below the floor of a plugin in the tree.
    // Those floors are soft in practice (a debug APK built fine at 8.11.1),
    // but nothing on a pull request compiles Android at all, so being under a
    // declared floor is a debt that would come due on a dev build, not here.
    //
    // 8.13 needs Gradle >=8.13 and we run 8.14; Flutter 3.47.1 knows AGP up to
    // 9.2 (`gradle_utils.dart`), so this is inside the range it validates.
    // Staying on 8.x deliberately: AGP 9 moves Kotlin into the plugin itself
    // (`android.builtInKotlin`) and is a migration, not a version bump.
    id("com.android.application") version "8.13.2" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // The R8 mapping and the UUID that ships in the APK; configured in
    // app/build.gradle.kts, which says why. #343, ADR 0013.
    id("io.sentry.android.gradle") version "6.24.0" apply false
}

include(":app")
