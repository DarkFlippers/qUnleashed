
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

сброс кеша 
flutter clean
Remove-Item -Recurse -Force build, .dart_tool -ErrorAction SilentlyContinue
flutter pub get
ie4uinit.exe -show
# если не помогло — жёсткий сброс:
taskkill /IM explorer.exe /F
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
