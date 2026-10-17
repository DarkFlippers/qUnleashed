import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
    // The Flutter plugin is what turns R8 on here: it sets
    // `isMinifyEnabled = true` on the release build type inside its own
    // `apply` (unless `-Pshrink=false`), and nothing in this file asks for
    // shrinking. Order between these two does not actually matter - the Sentry
    // plugin reads minification from the AGP variant inside `onVariants`, long
    // after both `apply`s - but it is written in the order it reads in.
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

// The R8 mapping - the one thing `sentry_dart_plugin` cannot upload, for a
// reason `.github/scripts/upload_r8_mapping.sh` records rather than this file.
// Without it every Java and Kotlin frame reaching Sentry is a renamed
// `w2.r.k`, and only the platform's own frames stay readable. #343.
//
// Two halves: the mapping goes to the project under a UUID, and the same UUID
// ships inside the APK so an event can say which mapping it belongs to. The
// UUID travels as `assets/sentry-debug-meta.properties`, not as manifest
// metadata, because a value derived from minification cannot be injected into
// either asset generation or manifest merging - both run before it exists - so
// the plugin transforms the finished assets artifact instead. The Android SDK
// `sentry_flutter` bundles reads it from there.
//
// The UUID is `nameUUIDFromBytes` over R8's own `pg_map_hash` line from the
// mapping, or over an MD5 of the file if R8 wrote none - a function of the
// mapping's content either way. So the two `flutter build apk --release` runs
// in `.github/scripts/build/android.sh` - one universal, one `--split-per-abi`
// - agree on it, and every APK in a release points at one mapping rather than
// at two that differ only in which one got uploaded. `verify_apks.sh` holds
// that invariant rather than trusting it.
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
    // `--no-upload` to sentry-cli, which returns before it authenticates - so
    // a build needs no token, touches no network, and nothing about Sentry's
    // availability can fail it, while the UUID is still minted and still
    // shipped in the APK. (The task can still fail for its own reasons: an
    // empty mapping collection is an `error()` inside it.) There is deliberately
    // no `org`, `projectName` or `authToken`: with nothing being sent they
    // would be dead configuration, and a second copy of two slugs that
    // `pubspec.yaml` already holds for `sentry_dart_plugin`.
    includeProguardMapping.set(true)
    autoUploadProguardMapping.set(false)

    // Of the rest, five flip a default that is on, and the mapping is the only
    // reason this plugin is here. `autoInstallation` would add
    // `io.sentry:sentry-android` and its integrations to the APK beside the
    // one `sentry_flutter` already pulls in. `tracingInstrumentation`
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
    // added: what decides this is whether R8 ran, not that the three that
    // exist today happen to be `debug`, `profile` and `release`.
    ignoredBuildTypes.set(
        provider {
            android.buildTypes.filterNot { it.isMinifyEnabled }.map { it.name }.toSet()
        },
    )
}
