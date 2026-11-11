allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Every Android subproject builds its native code with the NDK the app
// module uses, which is `flutter.ndkVersion` - 28.2.13676358 under the
// pinned Flutter.
//
// This is the 16 KB memory page requirement, and it was added for it
// (fe9e0db9). Play requires an app targeting Android 15 or later to support
// 16 KB pages, and what decides that for a shared library is the `p_align`
// its loadable segments ask for; NDK r27 made 16 KB the default, so pinning
// the version is what gets it. Without this block a plugin that compiles its
// own C - `flutter_libserialport` builds `libserialport` through its own
// `externalNativeBuild`, and declares no `ndkVersion` - would be linked by
// whatever NDK AGP defaults to, which moves on an AGP bump with nothing in
// this repository mentioning it.
//
// Flutter's own plugin only warns about a mismatch; it does not set this -
// and its warning cannot see a failed pin either: it reads a plugin's
// `ndkVersion ?: the app's`, so a plugin that declares none is recorded as
// already agreeing.
//
// `.github/scripts/elf_page_align.py` is the other half, and the two cover
// different things: this pin reaches everything built from source, and that
// gate reaches the prebuilt `.so` files a dependency ships in an AAR, which
// no build setting can realign. The gate would also notice this block being
// removed - but late, on a dev build after a five-platform run, so it is not
// a substitute for the pin.
//
// The same block raises `compileSdk` to the app's, for a reason the AGP 8.13
// bump made visible: `androidx.fragment` 1.7.1 and nineteen other transitive
// androidx artifacts declare a `minCompileSdk` of 34 in their AAR metadata,
// and three subprojects here were below it - `compileSdkVersion 31` in
// `super_native_extensions/android/build.gradle` and
// `irondash/engine_context/dart/android/build.gradle`, and `33` in the
// `usb_serial` package. AGP 8.11.1 built that; 8.13 fails
// `:super_native_extensions:checkReleaseAarMetadata` with twenty issues, and
// stops at the first subproject rather than listing the three.
//
// Upstream super_native_extensions is already on `compileSdk = 36`, so our two
// forks are behind; `usb_serial` is somebody else's package and will lag
// whenever androidx raises the floor again. That is why this is done here
// rather than as a pull request per repository: it is not a bridge until the
// forks catch up, it is standing policy, because `flutter.compileSdkVersion`
// exists only on the app module and a plugin can only hardcode a literal.
//
// Raised, never lowered. Raising `compileSdk` is the safe one of the three -
// it widens which APIs compile, where `targetSdk` opts into runtime behaviour
// and `minSdk` decides which devices can install - which is what Google's own
// message on this failure says. The one edge that is not free: recompiling
// against a newer `android.jar` can re-resolve an overload onto a method that
// is absent on an older device, which arrives as `NoSuchMethodError` at
// `minSdk` rather than at compile time. Nil risk for the Java here, but it is
// why this raises and never lowers rather than simply assigning.
subprojects {
    // `:app` holds both values, so it has to be evaluated before they can be
    // read. This also means `:app` is *already* evaluated when this block
    // reaches it, which is why the dispatch below is guarded: calling
    // `afterEvaluate` on an evaluated project throws.
    project.evaluationDependsOn(":app")

    val pinToApp = {
        // `as BaseExtension?` and deliberately not `as?`: a subproject with no
        // `android` extension answers null and is skipped, which is the point,
        // but an `android` extension of a type this does not know has to throw.
        // A safe cast would make the two indistinguishable and skip both pins
        // for every subproject at once, silently - and only one of the two is
        // backstopped by a failing build. That is reachable without an AGP 9
        // migration: `android.experimental.newDslInterfaces=true` swaps the
        // extension types while `BaseExtension` stays on the classpath.
        val own =
            extensions.findByName("android") as com.android.build.gradle.BaseExtension?
        if (own != null) {
            val app =
                project(":app").extensions.getByName("android")
                    as com.android.build.gradle.BaseExtension

            own.ndkVersion = app.ndkVersion

            // `compileSdkVersion` reads back as `android-36`, but also as
            // `android-37.0` (a minor version, and that platform is already
            // installable), `android-36-ext14` (an SDK extension),
            // `android-Baklava` (a preview) or an add-on string. So: the
            // leading integer, and three outcomes rather than two.
            fun levelOf(value: String?) =
                value?.removePrefix("android-")?.takeWhile { it.isDigit() }
                    ?.toIntOrNull()

            val declared = own.compileSdkVersion
            val appLevel = levelOf(app.compileSdkVersion)
            val ownLevel = levelOf(declared)
            if (appLevel == null) {
                // Nothing to raise *to*. Loud, because the alternative is the
                // AAR metadata check failing later and naming a submodule
                // instead of this line.
                error(
                    "cannot read the app's compileSdk ('${app.compileSdkVersion}'), " +
                        "so $path was left at '$declared'",
                )
            } else if (declared == null || (ownLevel != null && ownLevel < appLevel)) {
                // Declared nothing, or demonstrably lower. A value that parses
                // to nothing is left alone: it is likelier to be newer than
                // older, and writing the app's plain level over it would be the
                // lowering this block promises not to do.
                own.compileSdkVersion(appLevel)
            }
        }
    }

    // After the subproject's own script, not while its plugin is being
    // applied. `plugins.withId` fires when the plugin is *applied*, which in a
    // plugin's `build.gradle` is above its `android { }` block - so a value set
    // there is overwritten a few lines later by any subproject that declares
    // the same property. That is why `compileSdkVersion 31` kept winning, and
    // it is a hole the `ndkVersion` pin has had since fe9e0db9: the one plugin
    // in the tree that declares one, `jni`, happens to declare
    // `flutter.ndkVersion` - the same value - so the overwrite has been
    // harmless rather than absent.
    //
    // The ordering is structural, not luck: this callback is registered while
    // the *root* project is evaluated, AGP registers its own while the
    // *subproject* is, and Gradle fires them in registration order - so the
    // write always lands before AGP reads it.
    //
    // `:app` is the exception and does no work: the `evaluationDependsOn` above
    // has already evaluated it by the time the loop arrives, `afterEvaluate`
    // throws on an evaluated project, and pinning `:app` to its own values is a
    // no-op anyway. The assertion is there so that stops being a silent
    // assumption if Gradle ever changes when that happens.
    if (path == ":app") check(state.executed) else afterEvaluate { pinToApp() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
