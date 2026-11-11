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
// Flutter's own plugin only warns about a mismatch; it does not set this.
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
// androidx artifacts declare a `minCompileSdk` of 34 in their AAR metadata, and
// two submodules here still say `compileSdkVersion 31` -
// `super_native_extensions/android/build.gradle` and
// `irondash/engine_context/dart/android/build.gradle`. AGP 8.11.1 built that;
// 8.13 fails `:super_native_extensions:checkReleaseAarMetadata` with twenty
// issues. Upstream super_native_extensions is already on `compileSdk = 36`, so
// our forks are simply behind - but a plugin that lags is exactly the case this
// block exists for, and doing it here fixes every lagging plugin at once
// instead of one pull request per repository.
//
// Raised, never lowered: a subproject already on a newer SDK keeps it. Raising
// `compileSdk` is the safe one of the three - it only widens the APIs that
// compile, where `targetSdk` opts into runtime behaviour and `minSdk` decides
// which devices can install - which is what Google's own message on this
// failure says.
subprojects {
    // `:app` holds both values, so it has to be evaluated before they can be
    // read. This also means `:app` is *already* evaluated when this block
    // reaches it, which is why the dispatch below is guarded: calling
    // `afterEvaluate` on an evaluated project throws.
    project.evaluationDependsOn(":app")

    val pinToApp = {
        val own =
            extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (own != null) {
            val app =
                project(":app").extensions.getByName("android")
                    as com.android.build.gradle.BaseExtension

            own.ndkVersion = app.ndkVersion

            // `compileSdkVersion` reads back as `android-36`, so the level is
            // the tail. An unparseable value counts as older than the app's,
            // which is the direction that fails loudly rather than silently.
            val levelOf = { value: String? ->
                value?.substringAfterLast('-')?.toIntOrNull()
            }
            val appLevel = levelOf(app.compileSdkVersion)
            val ownLevel = levelOf(own.compileSdkVersion)
            if (appLevel != null && (ownLevel == null || ownLevel < appLevel)) {
                own.compileSdkVersion(appLevel)
            }
        }
    }

    // After the subproject's own script, not while its plugin is being
    // applied. `plugins.withId` fires when the plugin is *applied*, which in a
    // plugin's `build.gradle` is above its `android { }` block - so a value set
    // there is overwritten a few lines later by any subproject that declares
    // the same property. That is why `compileSdkVersion 31` kept winning in
    // two submodules, and it is a hole the `ndkVersion` pin has had since
    // fe9e0db9: it holds only because no plugin in the tree declares one.
    if (state.executed) pinToApp() else afterEvaluate { pinToApp() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
