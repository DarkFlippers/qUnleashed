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
    // 8.13.x, and the floor is not ours: `share_plus` 12 - in the tree now -
    // declares "Android Gradle Plugin >=8.12.1", so 8.11.1 was below the
    // declared floor of a plugin this app already builds. `device_info_plus`
    // 12 declares the same floor and is what the win32 chain wants next, so
    // this is also the step that unblocks it.
    //
    // Those floors are soft in practice (a debug APK built fine at 8.11.1),
    // but nothing on a pull request compiles Android at all, so being under a
    // declared floor is a debt that would come due on a dev build, not here.
    //
    // 8.13.2 and not the 8.12.1 minimum: both want Gradle >=8.13 and this
    // project runs 8.14, so the two cost the same.
    //
    // **The Kotlin line below moved in the same commit, and had to.** Flutter
    // validates the AGP/KGP pair from a table in `gradle_utils.dart`, and KGP
    // 2.2.x is allowed only with AGP below 8.12 - so `flutter analyze
    // --suggestions` reported "Incompatible AGP/KGP versions. AGP Version:
    // 8.13.2, KGP Version: 2.2.20". That makes the Kotlin bump a precondition
    // of clearing the plugins' floor at all rather than a separate nicety:
    // *any* AGP >=8.12 fails that check on 2.2.20. Note which command found
    // it - plain `flutter analyze` does not run project validators, so neither
    // does CI.
    //
    // Staying on 8.x is a stop and not a destination: Flutter already warns
    // that it wants AGP >=9.0.1 and Gradle >=9.1.0. AGP 9 is a migration of
    // its own - AGP 9.1 requires Gradle 9.3.1, and `android.newDsl` changes
    // which extension types exist, which the pin block in `build.gradle.kts`
    // reads by type.
    id("com.android.application") version "8.13.2" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    // 2.3.20 because AGP 8.13 requires it, per the table above: KGP 2.2.x
    // caps AGP at 8.12, and [2.3.10, 2.3.29] is the band that reaches 9.2.
    // 2.3.20 rather than 2.3.0 because it is also the floor Flutter's warning
    // already names (`DependencyVersionChecker.kt`), so one bump answers both.
    // Verified with `flutter analyze --suggestions`, which is the only command
    // here that runs that check.
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // The R8 mapping and the UUID that ships in the APK; configured in
    // app/build.gradle.kts, which says why. #343, ADR 0013.
    id("io.sentry.android.gradle") version "6.24.0" apply false
}

include(":app")
