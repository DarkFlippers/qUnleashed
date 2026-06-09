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
  <img src="screenshots/1_home.png" alt="Home screen" width="24%">
  <img src="screenshots/2_home.png" alt="Home screen with menu" width="24%">
  <img src="screenshots/3_connection.png" alt="Connection screen" width="24%">
  <img src="screenshots/4_install.png" alt="Firmware install screen" width="24%">
</p>
<p align="center">
  <img src="screenshots/5_run_installed.png" alt="Installed firmware screen" width="24%">
  <img src="screenshots/6_remoute.png" alt="Remote control screen" width="24%">
  <img src="screenshots/7_archive.png" alt="Archive screen" width="24%">
  <img src="screenshots/8_category.png" alt="Archive category screen" width="24%">
</p>
<p align="center">
  <img src="screenshots/9_filemanager.png" alt="File manager screen" width="24%">
  <img src="screenshots/10_fileselect.png" alt="File select screen" width="24%">
  <img src="screenshots/11_editor.png" alt="Text editor screen" width="24%">
  <img src="screenshots/12_appcatalog.png" alt="Apps catalog screen" width="24%">
</p>
<p align="center">
  <img src="screenshots/13_appinstall.png" alt="App install screen" width="24%">
  <img src="screenshots/14_tools.png" alt="Tools screen" width="24%">
  <img src="screenshots/15_tools_map.png" alt="FlipperMap pins screen" width="24%">
  <img src="screenshots/16_tools_map.png" alt="FlipperMap details screen" width="24%">
</p>
<p align="center">
  <img src="screenshots/17_tools_cli.png" alt="CLI tool screen" width="24%">
  <img src="screenshots/18_tools_mfkey.png" alt="Mfkey32 tool screen" width="24%">
  <img src="screenshots/19_tools_irlib.png" alt="Infrared library screen" width="24%">
  <img src="screenshots/20_tools_irdb.png" alt="IRDB browser screen" width="24%">
</p>
<p align="center">
  <img src="screenshots/21_tools_draw.png" alt="IRDB browser screen" width="24%">
  <img src="screenshots/22_tools_draw.png" alt="IRDB browser screen" width="24%">
</p>