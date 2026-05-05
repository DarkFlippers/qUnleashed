# qUnleashed

`qUnleashed` is a Flutter companion app for **Flipper Zero**, written from scratch as an alternative to **[Flipper Android App](https://github.com/flipperdevices/Flipper-Android-App.git)** and tailored for custom firmware, first of all **[Unleashed firmware](https://github.com/DarkFlippers/unleashed-firmware.git)** by **[DarkFlippers](https://github.com/DarkFlippers)**. The app is optimized around Unleashed-specific workflows: tracking firmware releases, reading changelogs, downloading updates and installing them directly from the app, while also reworking and extending parts of the original Flipper app experience.

At the moment the project includes:

- BLE and USB connection flow for Flipper Zero
- firmware-centric device overview with version, build date, storage and raw device info
- update flow for custom firmware with release tracking, changelogs, download and install
- remote control with live Flipper screen streaming and button input
- CLI access for terminal control
- clipboard/export actions for device data and keys
- app catalog with search, categories, sorting, app details and install actions
- UI and behavior tailored to Unleashed firmware specifics

## Screenshots

<p align="center">
  <img src="screenshots/connect.png" alt="Connect screen" width="32%">
  <img src="screenshots/device.png" alt="Device screen" width="32%">
  <img src="screenshots/apps.png" alt="Apps screen" width="32%">
</p>

## Mirror

https://git.aperturefox.ru/FlutterAPPs/qUnleashed
