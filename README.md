# qUnleashed

`qUnleashed` is a Flutter companion app for **Flipper Zero**, written from scratch as an alternative to **[Flipper Android App](https://github.com/flipperdevices/Flipper-Android-App.git)** and tailored for custom firmware, first of all **[Unleashed firmware](https://github.com/DarkFlippers/unleashed-firmware.git)** by **[DarkFlippers](https://github.com/DarkFlippers)**. The app is optimized around Unleashed-specific workflows: tracking firmware releases, reading changelogs, downloading updates and installing them directly from the app, while also reworking and extending parts of the original Flipper app experience.

## Features

qUnleashed keeps the familiar companion-app workflows from the original Flipper Android App and extends them for custom firmware, desktop-friendly USB access, stronger local archive tooling and additional tools.

- **Connection.** Like the original app, qUnleashed connects to Flipper Zero over BLE; unlike the original Android-only workflow, it also supports a desktop USB flow and uses the same app surface for device info, storage operations, CLI access and remote control.
- **Updater.** The original app focuses on the official firmware update flow; qUnleashed is firmware-centric for Unleashed/custom firmware, with release tracking, changelogs, downloads and in-app install.
- **Device info.** The original app shows connected Flipper status and firmware data; qUnleashed expands this view with Unleashed-oriented version, build date, storage state and raw device details.
- **Archive.** The original app provides Archive for saved Flipper keys; qUnleashed turns it into a local-first per-device archive with synced, remote-only, local-only and deleted states, favorites, restore actions and local/remote deletion.
- **Archive categories.** The original archive covers standard key types; qUnleashed additionally handles Sub-GHz, Wardriving, RFID 125, NFC, Infrared and iButton files, including known subfolders such as Wardriving autosaves.
- **File Manager.** The original app has a Flipper file manager; qUnleashed keeps this workflow and supports browsing `/ext`, hidden-file visibility, folder creation, rename, delete, download, upload and direct text editing.
- **Screen streaming and remote control.** The original app supports screen streaming and device controls; qUnleashed keeps live screen streaming, button input and adds convenient CLI access for low-level control.
- **Apps catalog.** The original app has FAP Hub; qUnleashed provides an apps catalog with search, categories, sorting, app details, screenshots and install actions.
- **Tools.** The original app includes NFC/Mfkey32 and infrared tools; qUnleashed keeps MIFARE Classic Mfkey32 recovery and adds a dedicated tools hub with Infrared library and FlipperMap.
- **Infrared library.** The original app supports the official infrared remote-control source and editor flow; qUnleashed keeps official-source compatibility and additionally supports IRDB by browsing the public `Lucaslhm/Flipper-IRDB` repository, searching the whole library, previewing and editing `.ir` files, saving remotes into the local archive or sending them straight to `/ext/infrared` on a connected Flipper.
- **FlipperMap.** The original app has no direct FlipperMap equivalent; qUnleashed parses synced archive files for latitude and longitude metadata, displays them on an interactive map, shows the current phone position, calculates distance, bearing and walking time, and links each pin back to the saved Flipper file.

## Screenshots

<p align="center">
  <img src="screenshots/connect.png" alt="Connect screen" width="32%">
  <img src="screenshots/device.png" alt="Device screen" width="32%">
  <img src="screenshots/apps.png" alt="Apps screen" width="32%">
</p>

