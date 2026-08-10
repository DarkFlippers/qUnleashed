## Main changes
- Version: 0.10.6 (build 10006), changes since 0.10.4 (build 10004)
* Apps: **The catalog picks its working mode by itself** - no more compatibility dialogs; when the firmware API is ahead of the catalog the app either builds the FAP from source (if a builder is available), installs the build of the nearest API the catalog has, or falls back to the apps manager. The chosen mode is shown as a badge in the catalog header and can be forced in Settings → Apps
* Apps: **Installs can be cancelled** - the progress button turns into CANCEL (and the manager sheet gets a Cancel entry); a job that has not started just leaves the queue, a running one stops at its next checkpoint and the partial file is dropped from the device
* Apps: **The install queue survives a flaky link** - installs are queued locally and a reconnect no longer kills them: tasks wait for the link and retry, and the queue is cleared only when the device is really gone. A second install no longer waits for the build server to be free
* Archive: **Rewritten text editor** - lines are rendered on demand, so big files open without freezing; syntax highlighting, a file from the device is downloaded to a temporary file first and uploaded back on save, and a JS script can be run right from the editor
* Archive: **Hidden files are shown by default** in the file browser
* Archive: **Category sync shows the same progress as the apps manager** - a bar with the file name and percentages under the toolbar instead of the file name in the app bar title
* Connection: **The live session continues across app reopens on Android** - the session stays alive with the process instead of dying with the activity, and system-connected devices are surfaced without a scan
* Settings: **Regrouped settings** - a new Apps page (catalog mode), and the theme, storage, notifications and Flibler pages moved under one place
* Flibler: **Faster start** - the build server availability check is cached instead of being repeated on every entry
* Android: the unused `READ_MEDIA_IMAGES` permission is gone
## Other changes
* Lib: new file layout - `app/`, `components/`, `pages/`, `services/`, settings pages under `option/pages/`, the FAP codec split into `codec/fap/`
* Flipperlib: slimmed down to the protobuf API, transports and DFU, protobuf regenerated; flipperlib and dartufbt are submodules pinned to the published packages
* Repository: dropped the one-shot legacy layout migration and the prebuilt `app-release.apk`
* Tests: catalog mode, apps settings page, text editor and FAP codec
