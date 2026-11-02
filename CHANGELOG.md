## Main changes
- Version: 0.17.2
## Other changes
- Fixed: an icon the renderer could not draw left an empty box and filed a crash report for every icon on screen, sixteen in one second on a cold start; the failure is now kept once, and a missing asset is told apart from a surface the engine refused (by @mishamyte | PR #448 | Fixes #441)
- Fixed: declining notification permission turned every disconnect into a crash report on iOS, because the app asked the system to post one anyway and never kept the answer it had already been given (by @mishamyte | PR #448 | Fixes #442)
