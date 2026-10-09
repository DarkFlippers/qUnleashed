## Main changes
- Version: 0.15.0 (build 15000), changes since 0.14.1 (build 14001)
* Archive: **Drag and drop in the file manager** - files and folders dropped from another app upload into the folder on screen, and files drag out of the Flipper into another app or onto the desktop. Keys drag out of the archive categories and favourites the same way, and a selection drags out whole
* Archive: **Replace, Skip or Rename when a file is already there** - asked once, before anything is written, instead of overwriting without a word. One answer can cover every conflict, and files whose checksum matches can be left alone
* Archive: **Transfers can be cancelled** - downloads, uploads and copies each get a Stop on their row or on the progress bar. On firmware that reads files in parts the read stops at the next part, and the bar keeps moving until the last one has arrived rather than freezing. Firmware that sends the whole file regardless is given eight seconds, after which the row clears without claiming the transfer was cancelled
* Archive: **Upload a whole folder** from the + menu, subfolders included
* Archive: **One large download at a time** - a file bigger than one firmware packet (512 bytes) waits for the download in progress to finish instead of piling a second one onto the link; small files still open straight away. Opening and sharing the same file at once downloads it once
* Tools: **Sub-GHz seed recovery for FAAC SLH, Genius, BFT and Erreka remotes** - reads a capture from the Flipper's `seed_capturer` app, recovers the seed in the app with no server, and saves a transmittable `.sub` under Sub-GHz -> Saved. A capture that missed a few presses still solves, so the whole burst does not have to be caught. A capture can now be deleted from its own row, including ones taken before this shipped
* Tools: **Hardnested MIFARE recovery actually runs** - it failed on every attempt with an engine error before doing any work. It now has a Stop, refuses to start without the memory it needs, and its brute force uses the vector instructions the CPU has instead of the slowest variant
* Tools: **MIFARE recovery says what it is doing and keeps what it found** - keys already known are skipped, a failed save retries the write rather than the whole run, the user dictionary is backed up before it is overwritten, and Stop also works while the logs download
* Language: **Ukrainian** - the picker names every language in that language, and a language nobody has translated yet is no longer offered as English under another name
## Other changes
* Connection: Remote Control follows the Flipper you are linked to, and the CLI stays on its Flipper across reconnects
* Desktop: closing the window disconnects every link first, so the USB serial port is released instead of staying held by a process that would not exit
* Fixed: a double click on a file opens it once, not twice, and the firmware install button cannot start two installs
* Fixed: Flibler stays in the Tools menu when a build server is set or an earlier catalog build failed, since it can still build
* Fixed: an `application.fam` with an `if`, `for`, `def` or annotation now reads - 696 of 696 manifests on hand, against 693
* Names: one rule for what a file name may not contain, used by every name prompt, and Sub-GHz names are measured in bytes, so a long Cyrillic name is no longer cut in half on the Flipper
* Archive: file colours in the file manager match their archive categories
* Dependencies: drag and drop uses DarkFlippers forks of super_native_extensions and irondash, built for Android's 16 KB pages; macOS builds target 12.0; flipperlib reads files in parts (protocol 0.30)
* Translations: obsolete strings leave Crowdin, plurals no longer trip its checks, and `docs/translating.md` says what a translator needs to know
* Architecture: ADR 0013 adds a third log level for failures nothing records, and ADR 0014 settles versioning on SemVer and the build number it forces
