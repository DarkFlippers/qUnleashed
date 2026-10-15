## Main changes
- Version: 0.17.0
- Localization: translated app to Belarusian, Croatian, French, German and Spanish (by @mishamyte | PR #320, #323)
- Notifications: keep push alive through the APNS token race, and stop pretending macOS has push (by @mishamyte | PR #325 | Closes #324)
- Diagnostics: **Screen replays show the interface again** - the SDK's blanket text mask was greying out every button, tab and title, so a recording of a failure showed nothing anybody could read (by @mishamyte | PR #334 | Closes #331)
- Settings: a setting that does not persist is recorded instead of lost in silence, and the home-screen widget stops showing a look that was never saved (by @mishamyte | PR #335 | Closes #313)
## Other changes
- Archive: stop a right click in the text editor crashing the frame on every desktop target (by @mishamyte | PR #329 | Closes #328)
- Translations: Stop the Crowdin sync opening an empty pull request every night (by @mishamyte | PR #327 | Closes #326)
- Fixed: a push topic call that failed while offline uploaded a full session replay from every iOS launch, instead of the buffered minute before a failure (by @mishamyte | PR #334 | Closes #332)
- Diagnostics: device names, serials, BLE addresses and card identifiers are no longer replaced with placeholders in the reports sent to the developers, so a report says which unit and which card it is about (by @mishamyte | PR #334)
- Crash reports: Windows and Linux builds carry debug information now, so a native crash names the function and line instead of the nearest export (by @mishamyte | PR #330 | Closes #310)
