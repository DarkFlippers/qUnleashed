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
subprojects {
    project.evaluationDependsOn(":app")

    listOf("com.android.application", "com.android.library").forEach { pluginId ->
        plugins.withId(pluginId) {
            val appNdkVersion =
                (project(":app").extensions.getByName("android")
                    as com.android.build.gradle.BaseExtension).ndkVersion
            (extensions.getByName("android") as com.android.build.gradle.BaseExtension)
                .ndkVersion = appNdkVersion
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
