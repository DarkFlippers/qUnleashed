## Main changes
- Version: 0.10.4 (build 10004)
* Apps: **Build catalog apps from source when the device API does not match** - the mismatch dialog now offers three ways out: compatibility mode, ignore the warning, or apps manager only; in source mode the install engine fetches the catalog source bundle and compiles the FAP against the firmware SDK instead of pulling a prebuilt one
* Flibler: **New tool that builds a Flipper app from a folder or a repo link** - one field takes a local path or a GitHub URL (branch and subfolder included), the page keeps recent projects, shows the FAP facts after a build and can launch the result on the device (Beta)
* Flibler: **Local or server builds** - desktop compiles with its own toolchain, everything else sends the job to the build server; the choice lives in the Flibler settings next to the SDK channel and the SDK index source
* Flibler: **Signed client for the remote build server** - requests are signed, the server keeps a build queue and a cache, so a phone gets the same FAP without an ARM toolchain
* dartufbt: **Native Dart port of ufbt** - SDK deployment over `directory.json`, ARM toolchain deployment and a full FAP builder that shares `~/.ufbt` with the Python ufbt, so an existing setup is reused as is; the output is byte-identical to ufbt (verified on `air_mouse` and `example_images`, including the debug ELF) and heatshrink is ported from the firmware encoder
* Connection: **The live session continues across app reopens on Android** - a cached FlutterEngine keeps the isolate, and the BLE session inside it, alive with the process instead of dying with the activity; the foreground service reconciles against the real session on isolate start and no longer auto-restarts headless, and system-connected devices are surfaced without a scan
* Apps: **An installed app lands in the manager without a rescan** - the install engine hands the app over to the device list right after the install
* Apps: **Reworked manager table** - fap metadata is read from the app itself, the facts panel works from a bare `FapInfo`, and the rows follow the catalog layout
* Archive: **Category sync shows the same progress as the apps manager** - a bar with the file name and percentages under the toolbar instead of the file name in the app bar title
## Other changes
* Lib: new file layout - `app/`, `components/`, `pages/`, `services/`; a screen of another feature is opened through a route, not by importing its page
* Flipperlib: slimmed down to the protobuf API, transports and DFU - the GPS and Network RPC responders, the device info watch and the logging facade moved into the app
* Repository: dropped the one-shot legacy layout migration
* Android: removed the unused `READ_MEDIA_IMAGES` permission
* Repo: flipperlib and dartufbt are submodules now, and the prebuilt `app-release.apk` is gone from the tree
* Workflow: release builds get the build server secrets
* Tools: Flibler is listed on desktop only - there is no local toolchain elsewhere, so those source builds go through the server