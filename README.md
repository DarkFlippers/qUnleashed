# qUnleashed

`qUnleashed` is a Flutter companion app for **Flipper Zero**, written from scratch as an alternative to **[Flipper Android App](https://github.com/flipperdevices/Flipper-Android-App.git)** and tailored for custom firmware, first of all **[Unleashed firmware](https://github.com/DarkFlippers/unleashed-firmware.git)** by **[DarkFlippers](https://github.com/DarkFlippers)**. The app is optimized around Unleashed-specific workflows: tracking firmware releases, reading changelogs, downloading updates and installing them directly from the app, while also reworking and extending parts of the original Flipper app experience.

## Features

qUnleashed keeps the familiar companion-app workflows from the original Flipper Android App and extends them for custom firmware: USB support on mobile **and** desktop, firmware repair from DFU mode, phone GPS/internet sharing, a stronger local archive and a bigger toolbox.

### Connection

- **BLE and USB on every platform that allows it.** qUnleashed connects to Flipper Zero over BLE on all supported platforms, and over a USB serial cable on **Android, Windows, macOS and Linux** (iOS is BLE-only — Apple does not expose USB serial to apps). Both transports drive the same app surface: device info, archive sync, file manager, apps, remote control and CLI.
- **Multiple devices.** The app remembers known Flippers, keeps warm sessions for them, switches between devices instantly and reconnects automatically (a plugged-in USB device takes priority over the last BLE one).
- **Reliable background link.** On Android a foreground service keeps the BLE connection alive while the app is in the background.

### Firmware

- **Updater.** Firmware-centric for Unleashed: release/dev channel tracking with changelogs, downloads and in-app install, including Unleashed variants (base, extra apps, compact). Official firmware channels are supported as well.
- **Repair from DFU mode.** If the firmware is broken, qUnleashed can fully re-flash the device over USB in DFU/recovery mode — core firmware, radio stack and FUS handling — mirroring qFlipper's Full Repair flow.
- **Release notifications.** Optional push notifications for new Unleashed and official firmware releases, with a separate opt-in for dev-channel builds.

### Device

- **Device info.** Connected Flipper status expanded with firmware version and build date, battery details, internal/external storage state and a raw device-details sheet.
- **GPS and internet sharing.** On firmware builds with the RPC GPS/network extension, the app feeds the phone's location to Flipper apps and proxies network connections from the Flipper through the phone's internet, with live TX/RX traffic stats on the device card.
- **Remote desktop.** Live screen streaming and button control, physical-keyboard input on desktop, screenshot export and GIF recording of the Flipper screen.
- **Command line.** A full CLI terminal session on the device (USB; not available on iOS).

### Archive

- **Local-first per-device archive** with synced, remote-only, local-only and deleted states, favorites, restore actions and local/remote deletion.
- **Categories.** Sub-GHz, Wardriving (including autosaves), RFID 125, NFC, Infrared, iButton, Bad USB and JavaScript files.
- **Launch from the app.** Saved keys can be emulated/launched on the connected Flipper straight from the archive — NFC, RFID and iButton via RPC emulation, Sub-GHz, Infrared, Bad USB and JavaScript via the matching Flipper app.
- **Editing and sharing.** Built-in text editor with Flipper file-format syntax highlighting, plus sharing of remote files.
- **File Manager.** Browse both `/ext` and `/int`, hidden-file visibility, folder creation, rename, delete, download, upload and direct text editing.

### Apps

- **Apps catalog.** Search, categories, sorting, app details and screenshots on top of the official catalog, with install, update and delete actions and detection of already-installed and preinstalled apps.

### Tools

- **Pixel Draw.** A pixel-art editor for the Flipper screen: project manager, multi-frame animations, dolphin animation import and live preview directly on the device display.
- **Extract MIFARE Keys.** MIFARE Classic Mfkey32 key recovery from device nonces, computed natively on the phone.
- **Remotes Library.** Official infrared remote source plus the public `Lucaslhm/Flipper-IRDB` repository: browse by brand/category, search the whole library, preview and edit `.ir` files, save remotes into the local archive or send them straight to `/ext/infrared`.
- **Pulse Plotter.** Visualize raw Sub-GHz/Infrared/RFID pulse captures with zooming, histograms and slicing helpers — open captures right from the archive.
- **Saved Locations.** Parses synced archive files for latitude/longitude metadata, shows them as pins on an interactive map with the current phone position, distance, bearing and walking time, and links each pin back to the saved Flipper file.

## Support ApertureFox projects
<p align="left">
  <a href="https://boosty.to/apfxtech/donate">
    <img src="https://img.shields.io/badge/Boosty-Support-F15F2C?style=for-the-badge&logo=boosty&logoColor=white" alt="Boosty"/>
  </a>
  <a href="https://yoomoney.ru/fundraise/1IV33POM6H4.260711">
    <img src="https://img.shields.io/badge/YooMoney-RU%20only-8B3FFD?style=for-the-badge&logo=yoomoney&logoColor=white" alt="YooMoney"/>
  </a>
</p>
GRAM (TON): UQAntlM9gsL92ODiNxNbH4SPpfL5OpYm2gbbuNYZuE9vDEYK

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