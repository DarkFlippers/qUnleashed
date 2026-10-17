import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
    // After the Flutter plugin, because that is what turns R8 on here: it sets
    // `isMinifyEnabled = true` on the release build type inside its own
    // `apply`, and nothing in this file asks for shrinking. The Sentry plugin
    // skips a variant that is not minified, so it has to be applied after the
    // line that minifies one.
    id("io.sentry.android.gradle")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use(::load)
    }
}

fun keystoreProperty(name: String): String? = keystoreProperties.getProperty(name)

val hasReleaseSigningConfig = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
).all { !keystoreProperty(it).isNullOrBlank() }

android {
    namespace = "com.darkflippers.qunleashed"
    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.darkflippers.qunleashed"

        minSdk = 29
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true

        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=none")
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            // Top-level CMake builds both qunleashed_mfkey32 and qunleashed_hardnested.
            path = file("../../lib/modules/cpp/CMakeLists.txt")
        }
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = rootProject.file(keystoreProperty("storeFile")!!)
                storePassword = keystoreProperty("storePassword")
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// The R8 mapping - the one thing `sentry_dart_plugin` cannot upload, because a
// mapping is not a debug file and is not in the directories it hands to
// sentry-cli. Without it every Java and Kotlin frame reaching Sentry is a
// renamed `w2.r.k`, and only the platform's own frames stay readable. #343.
//
// Two halves, both of them this plugin's: the mapping goes to the project
// under a UUID, and the same UUID ships inside the APK so an event can say
// which mapping it belongs to. The UUID travels as
// `assets/sentry-debug-meta.properties` rather than as manifest metadata -
// the plugin cannot hook manifest merging, because the merge is a dependency
// of the minification its UUID is derived from - and the Android SDK
// `sentry_flutter` bundles reads it from there.
//
// The UUID is `nameUUIDFromBytes` over the mapping's own contents. So the two
// `flutter build apk --release` runs in `build/android.sh` - one universal,
// one `--split-per-abi` - agree on it, and every APK in a release points at
// one mapping rather than at two that differ only in which one got uploaded.
//
// This file does not send anything, and no release name appears below. The
// send is `upload-debug-symbols`, after the APKs exist, with the UUID read
// back out of a built APK and the mapping taken from R8's own output
// directory - so the thing uploaded is addressed by the identifier that
// actually shipped rather than by one re-derived later.
//
// Sending from here was tried and is wrong. The plugin's `asSentryCliExec`
// throws `SentryCliException` from its own `doLast` on a non-zero exit, and
// `hookWithAssembleTasks` makes the upload a finalizer of `assembleRelease` -
// so an unreachable Sentry fails the build, `set -e` in `android.sh` skips the
// copy into `dist/`, and a release that was already built is discarded over
// symbolication. Nothing here can decline that: the throw is in an action this
// file does not own, and `isIgnoreExitValue` is already true, which is exactly
// why the exit code reaches that `doLast` instead of Gradle. Hence `false`
// below rather than a catch above.
sentry {
    // The UUID, and never the upload. `false` makes the plugin pass
    // `--no-upload` to sentry-cli, which returns before it authenticates - so a
    // build needs no token, touches no network, and cannot fail here, while the
    // UUID is still minted and still shipped in the APK. There is deliberately
    // no `org`, `projectName` or `authToken`: with nothing being sent they
    // would be dead configuration, and a second copy of two slugs that
    // `pubspec.yaml` already holds for `sentry_dart_plugin`.
    includeProguardMapping.set(true)
    autoUploadProguardMapping.set(false)

    // Of the rest, five flip a default that is on, and the mapping is the only
    // reason this plugin is here. `autoInstallation` would add
    // `io.sentry:sentry-android` and its integrations to the APK beside the
    // 8.56.0 `sentry_flutter` already pulls in. `tracingInstrumentation`
    // rewrites bytecode for spans nothing opens from Java here, and
    // `runtimeOptimizations` tunes an SDK start-up that happens in Dart.
    // `includeDependenciesReport` ships a list of Java dependencies in the
    // APK's assets. `telemetry` reports every build, a contributor's local one
    // included, to Sentry's own DSN.
    //
    // `uploadNativeSymbols` is already off and is stated anyway, because it is
    // the one default whose changing would be actively wrong here rather than
    // merely unwanted: `sentry_dart_plugin` is the single place that sends the
    // native debug files, for all six targets, and a second uploader is how
    // the Android `.so` symbols would arrive twice.
    uploadNativeSymbols.set(false)
    includeDependenciesReport.set(false)
    telemetry.set(false)
    autoInstallation { enabled.set(false) }
    tracingInstrumentation { enabled.set(false) }
    runtimeOptimizations { enabled.set(false) }

    // Only a minified variant has a mapping, and on any other the plugin still
    // transforms the assets to inject a UUID that points at nothing. Derived
    // rather than listed, so a build type added later is covered the day it is
    // added: what decides this is whether R8 ran, not that the two Flutter
    // creates today happen to be called `debug` and `profile`.
    ignoredBuildTypes.set(
        provider {
            android.buildTypes.filterNot { it.isMinifyEnabled }.map { it.name }.toSet()
        },
    )
}
