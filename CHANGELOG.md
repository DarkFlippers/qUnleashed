## Main changes
- Version: 0.14.0 (build 14000), changes since 0.13.0 (build 13000)
* Tools: **MIFARE key recovery works on iOS and macOS** - it never had. Reading a `.nested.log` ended with "Candidate generation is unavailable on this build" for static-encrypted cards, and mfkey32 and weak-nested recovery were just as dead, failing with a generic error instead of that one. The attack code was compiled into the app and then discarded at link time, because nothing outside Dart names those entry points in a way the linker can see. Reported from a dev build on iOS 26.5.2
* Tools: **A build missing its recovery engine says so on every screen** - three of the four recovery paths reported it as a failure that could equally have been a full card or a key the tag refused, which sends anyone debugging it after the wrong thing
## Other changes
* Release: the macOS and iOS builds now refuse to package an app whose recovery entry points did not survive linking, and a test on every pull request holds the two source-level pieces that keep them there. Neither existed when this shipped broken, and no Dart test could have caught it - that suite never links an Apple binary
* Architecture: ADR 0013 proposes Sentry for crash and error reporting, and ADR 0014 the build identity it would report against. Both are proposals; nothing is wired up
* Docs: the hardnested build notes no longer assert which binary the pod's code lands in on Apple, which nobody here has been able to observe. The release check was written not to need the answer
