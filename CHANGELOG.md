## Main changes
- Version: 0.17.2
## Other changes
- Changed: this release moves to a newer Bluetooth library, which writes device addresses in a different case than the one your remembered Flipper was saved under; the saved address is carried over as soon as the app reads it, so the device list and auto-connect carry on working (by @mishamyte | PR #450 | Fixes #444)
- Fixed: on Linux the app filed a crash report at every launch on a machine with no Bluetooth stack installed, and left Bluetooth dead for the rest of the session even after the stack was installed; it now checks whether the system can bring BlueZ up before asking it to, and installing `bluez` is noticed on the next scan (by @mishamyte | PR #449 | Fixes #443)
- Fixed: an icon the renderer could not draw left an empty box and filed a crash report for every icon on screen, sixteen in one second on a cold start; the failure is now kept once, and a missing asset is told apart from a surface the engine refused (by @mishamyte | PR #448 | Fixes #441)
- Fixed: declining notification permission turned every disconnect into a crash report on iOS, because the app asked the system to post one anyway and never kept the answer it had already been given (by @mishamyte | PR #448 | Fixes #442)
