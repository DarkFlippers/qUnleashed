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

        // The ABI floor the universal APK would otherwise lose. Flutter sets
        // this itself, but only on the branch where ABI splits are *off* - and
        // the `splits` block below asks for them, which took it away. The
        // universal APK then came back carrying `lib/x86/` from six
        // third-party dependencies with no `libflutter.so` and no `libapp.so`
        // beside them: Play reads it as supporting x86, installs it on an x86
        // device, and the app dies at launch with no engine to start. That is
        // the failure Flutter's comment on `configureAbis` describes, and
        // `verify_apks.sh` is what refused it. #361.
        //
        // Flutter's own list rather than a third copy of the three names: it is
        // a `@JvmStatic val` on a public object and the plugin is already on
        // this build's classpath, so if an upgrade moves it this stops
        // compiling - loud, rather than a silently narrowed APK.
        //
        // **This block and `isUniversalApk` below have to change together.**
        // Flutter's warning that `abiFilters` "would break builds when
        // --splits-per-abi is used" is exactly right: AGP's
        // `checkSplitsConflicts` refuses the pair - measured, with the two
        // lists *identical*, so it is not about them disagreeing - and the one
        // thing that makes it legal here is that it returns early when
        // `isUniversalApk` is set. Take the universal APK away and keep this,
        // and every `--split-per-abi` build dies with "Conflicting
        // configuration ... in ndk abiFilters cannot be present when splits
        // abi filters are set".
        //
        // Nor is this the same list the splits use, though both derive from
        // `DEFAULT_PLATFORMS` and so agree whenever `target-platform` is
        // unset - which is every CI build, since `derive_version.sh` passes
        // only `--build-name`, `--build-number` and the dart-defines. A local
        // `--split-per-abi --target-platform=android-arm64` makes the splits
        // `[arm64-v8a]` against this list's three, which no longer errors and
        // gives a universal APK wider than its own Flutter libs - the x86 bug
        // one ABI over. `verify_apks.sh` is what notices, by reading the ABIs
        // each artifact actually carries.
        //
        // Unconditional, where Flutter's own write is gated on
        // `-Pdisable-abi-filtering`; that escape hatch is inert here, and its
        // only effect would be to reinstate the crash above.
        ndk {
            abiFilters.addAll(com.flutter.gradle.FlutterPluginConstants.PLATFORM_ABI_LIST)
        }

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

    // One invocation, four APKs, one R8 run - which is the point, rather than
    // the minute it saves. `build/android.sh` used to build the whole release
    // twice, once for the universal APK and once with `--split-per-abi`, and R8
    // wrote over `mapping.txt` on the second pass. So the mapping that got
    // uploaded came from one build and the UUID it was filed under came from
    // the other's APK, which is correct only while R8 is deterministic across
    // the two. It is, and nothing made it so. Now there is one mapping and one
    // UUID because there is one R8 run. #361.
    //
    // Only `isUniversalApk` here. Flutter's plugin owns the rest: with
    // `--split-per-abi` it sets `isEnable`, calls `reset()` and hardcodes
    // `isUniversalApk = false` inside its own `apply` - which runs eagerly, so
    // this block always wins rather than racing it. Flipping this one value
    // leaves the split set Flutter's.
    //
    // It is also what makes `defaultConfig.ndk.abiFilters` above legal at all;
    // see the paragraph there before removing either. And if a later Flutter
    // moved `configureAbis` into an `afterEvaluate` this override would
    // silently lose - `android.sh` hard-fails on the missing `app-release.apk`
    // rather than publishing three artifacts.
    //
    // Inert unless splits are on - AGP reads `isUniversalApk` only when the
    // filter set is non-empty - so `flutter run` and a plain
    // `flutter build apk` are unaffected.
    splits {
        abi {
            isUniversalApk = true
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
// mapping's content either way. Every APK in a release now carries the same
// one because `.github/scripts/build/android.sh` runs R8 once, which the
// `splits` block above is what allows; it used to build twice and lean on R8
// being deterministic across the two. `verify_apks.sh` still checks they
// agree, which is now what would catch a regression back to two runs.
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
