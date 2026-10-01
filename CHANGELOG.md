## Main changes
- Version: 0.13.0 (build 13000), changes since 0.12.1 (build 12001)
* Everywhere: **A failure now says why** - the single theme of this release. Roughly thirty surfaces that used to show "nothing to show", a spinner that never ended, or a bare "it did not work" now carry the reason the Flipper or the phone gave. Deleting a key while an app is running says `ERROR_APP_SYSTEM_LOCKED` instead of reappearing seconds later in silence; a restore onto a full card says so; a key that will not open, a send that did not go, a setting that did not stick and an emulation that never started all name their cause
* Connection: **The picker says which link to let go of** - the app holds at most two links at once, and asking for a third used to fail with a generic "Connection failed". It now says so and tells you to disconnect one. New error kind in flipperlib rather than a reused one, because the fix differs from the system's own pairing limit
* Connection: **Auto-connect failures are visible** - a cable that does nothing, forever, used to be a log line nobody reads. The device page now carries a dismissible card naming the cause, since a timer-driven attempt has no gesture to hang a dialog on and a toast would fade while the condition did not
* Device: **A refused reboot is no longer silent** - firmware that declines to reboot (an app is running, or it is busy) used to look exactly like a reboot that happened: the page went to disconnected while the Flipper sat there unchanged
* Tools: **Wrist Remote** - the Flipper can be driven from Android media controls, including a wrist device, with each half of a failure named rather than guessed from its type
* Tools: **An in-app log screen**, and a route for errors nothing else catches - what a shipped build can be asked for after something goes wrong
* Apps: **An install says which way it went** - over the link, or by DFU
* Apps: **One bad entry no longer costs the page** - a malformed catalogue entry, cached app list row or ATP pack member is skipped and named instead of emptying the screen
* Archive: **A pull to refresh waits for the refresh** - four tables ended their spinner in the same frame they started it, while the download or the device scan had not begun
* Archive: **The map picks up where it left off after a reinstall**, and the desktop layout is simpler
* Firmware: **An offline launch still shows the directory** it last fetched, instead of nothing
* Settings: **The update channel and build variant are remembered**; Storage no longer reports a size or a clear it did not manage
* Android: GIF exports are compressed rather than expanded, and the GNSS fix is requested at startup
## Other changes
* Quality: four ratchet tests now hold lines that used to drift - failures reported only at a level release builds drop, catches that record nothing, classes that reach for the device instead of being handed it, and futures nobody awaits or handles. The last went from 119 sites to 22, each remaining one named with its reason
* Quality: 1197 test cases across 106 files, up from 26 files at 0.12.1, and CI runs them in a random order so none of them depends on being first
* Quality: `unawaited_futures` is enforced; `flipperlib` has its own suite, including the RPC queue and the connection-error classifier
* Architecture: fourteen decision records under `docs/adr/`, with the ones that carried migration work closed by evidence rather than opinion - `ChangeNotifier` stays, dependencies are passed in, absence is `null`, feed decoding is tolerant
* Localization: English is the only translation source anyone can edit, enforced in CI, so a Crowdin sync can no longer overwrite a language
* Release: every release publishes `SHA256SUMS`, the Android APKs are verified to contain an app before publishing, the workflows are linted, Dart formatting is enforced, and the build path can be exercised without cutting a release
* Fixed: a reconnect that raced the initial open was dropped; an interrupted IR library refresh cost the user their library; apps removed from the device still showed as installed; a cached response body was decoded on the calling isolate; the apps table header overflowed its row at every window width
