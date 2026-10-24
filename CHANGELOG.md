## Main changes
- Version: 0.17.1
## Other changes
- SubGHz: Write a KeeLoq .sub with the frame the firmware reads back, and list BFT (by @mishamyte | PR #395)
- Connection: Bump flipperlib: Android's service discovery that failed to classify (by @mishamyte | PR #394 | Closes #393)
- Crash reports: Treat a platform that cannot answer about location as a readiness (by @mishamyte | PR #392)
- Crash reports: Stop guarded rejecting when its task returns something (by @mishamyte | PR #391 | Fixes #390)
- Crash reports: Stop asking the SDK for the package list it cannot collect (by @mishamyte | PR #389 | Closes #388)
- Connection: Bump flipperlib: the service enumeration that failed to classify (by @mishamyte | PR #387 | Closes #386)
- Connection: Bump flipperlib: the Bluetooth permission refused at connect time (by @mishamyte | PR #385 | Fixes #384)
- Archive: Do not word a cancelled transfer off a page that has gone (by @mishamyte | PR #382)
- Connection: Connect to a Flipper with no rpcStatus, and read the GATT status properly (by @mishamyte | PR #380)
- Linux: Fix the two desktop Linux failures 0.17.0 reported (by @mishamyte | PR #379)
- Fixed: Fix the four failures 0.17.0's first day reported (by @mishamyte | PR #378)
