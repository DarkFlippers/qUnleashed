# qUnleashed

## Mirror
https://git.aperturefox.ru/FlutterAPPs/qUnleashed

## TODO
1. I do not want to spend time fighting with certificates on iOS and macOS. I have a MacBook, but I would appreciate it if someone could set up USB and BLE drivers for Apple devices and test them.
2. Support for Android, Windows, Web, and Linux will be added when I have free time. iOS and macOS support can also be added if someone contributes a commit.
3. Rework the default firmware channels for Unlshd:
   `2-ofw`, `3-moment`, `4-chronos`.
   Each channel should have a rounded square logo, a name label, and a gray version label.
4. Support both release and development builds.
5. Add controls and a gaming mode.
6. Add a file manager.
7. Make the last tab a terminal in debugger mode, plus a logger and a terminal for CLI mode.
8. By default, `cli -> proto`. The flow still needs to be designed properly so switching between modes is fast and convenient.
9. The app color theme should match the installed firmware, or the firmware selected during installation.
10. https://pub.dev/packages/dynamic_app_icon_flutter_plus

## Notes for Developers

### Sources
1. `git clone https://github.com/flipperdevices/qFlipper.git .sources/qflipper`
2. `git clone https://github.com/flipperdevices/lab.flipper.net.git .sources/labflipper`

### Proto
```powershell
flutter pub global activate protoc_plugin

$PLUGIN = "$env:LOCALAPPDATA\Pub\Cache\bin\protoc-gen-dart.bat"
Test-Path $PLUGIN

cd packages\protobuf
flutter pub get
cd ..\..

$VERSION = "34.1"
$ZIP = "packages\protobuf\tools\protoc.zip"
$URL = "https://github.com/protocolbuffers/protobuf/releases/download/v$VERSION/protoc-$VERSION-win64.zip"

mkdir packages\protobuf\tools -Force
Invoke-WebRequest $URL -OutFile $ZIP
Expand-Archive $ZIP -DestinationPath "packages\protobuf\tools\protoc" -Force

.\packages\protobuf\tools\protoc\bin\protoc.exe --version

$PROTOC = ".\packages\protobuf\tools\protoc\bin\protoc.exe"
$PLUGIN = "$env:LOCALAPPDATA\Pub\Cache\bin\protoc-gen-dart.bat"

$PROTO_DIR = ".\packages\protobuf\proto\flipperzero"
$OUT_DIR = ".\packages\protobuf\lib\src\generated"

mkdir $OUT_DIR -Force

Remove-Item "$OUT_DIR\*.pb*.dart" -Force -ErrorAction SilentlyContinue

& $PROTOC `
  "-I$PROTO_DIR" `
  "--plugin=protoc-gen-dart=$PLUGIN" `
  "--dart_out=$OUT_DIR" `
  "$PROTO_DIR\flipper.proto" `
  "$PROTO_DIR\storage.proto" `
  "$PROTO_DIR\system.proto" `
  "$PROTO_DIR\application.proto" `
  "$PROTO_DIR\gui.proto" `
  "$PROTO_DIR\gpio.proto" `
  "$PROTO_DIR\property.proto" `
  "$PROTO_DIR\desktop.proto"

@"
library flipperzero;

export 'src/generated/flipper.pb.dart';
export 'src/generated/storage.pb.dart';
export 'src/generated/system.pb.dart';
export 'src/generated/application.pb.dart';
export 'src/generated/gui.pb.dart';
export 'src/generated/gpio.pb.dart';
export 'src/generated/property.pb.dart';
export 'src/generated/desktop.pb.dart';
"@ | Set-Content packages\protobuf\lib\flipperzero.dart -Encoding UTF8
```

Based on these commands, a generator/build script should be written for Linux, macOS, and Windows.
