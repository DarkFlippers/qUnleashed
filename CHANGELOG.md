## Main changes
- Version: 0.17.0
- Notifications: keep push alive through the APNS token race, and stop pretending macOS has push (by @mishamyte | PR #325 | Closes #324)
- Diagnostics: **Screen replays show the interface again** - the SDK's blanket text mask was greying out every button, tab and title, so a recording of a failure showed nothing anybody could read (by @mishamyte | PR #334 | Closes #331)
## Other changes
- Translations: Stop the Crowdin sync opening an empty pull request every night (by @mishamyte | PR #327 | Closes #326)
- Fixed: a push topic call that failed while offline uploaded a full session replay from every iOS launch, instead of the buffered minute before a failure (by @mishamyte | PR #334 | Closes #332)
- Diagnostics: device names, serials, BLE addresses and card identifiers are no longer replaced with placeholders in the reports sent to the developers, so a report says which unit and which card it is about (by @mishamyte | PR #334)
