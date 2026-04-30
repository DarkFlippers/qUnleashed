$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Split-Path -Parent $ScriptDir
$RepoDir = Split-Path -Parent (Split-Path -Parent $LibDir)

$Version = if ($env:PROTOC_VERSION) { $env:PROTOC_VERSION } else { "34.1" }
$ZipPath = Join-Path $ScriptDir "protoc.zip"
$ProtocDir = Join-Path $ScriptDir "protoc"
$ProtocBin = Join-Path $ProtocDir "bin/protoc.exe"
$ProtoDir = Join-Path $LibDir "proto/flipperzero"
$OutDir = Join-Path $LibDir "generated"
$ExportFile = Join-Path $LibDir "protobuf.dart"
$Plugin = Join-Path $env:LOCALAPPDATA "Pub\Cache\bin\protoc-gen-dart.bat"
$Url = "https://github.com/protocolbuffers/protobuf/releases/download/v$Version/protoc-$Version-win64.zip"

Write-Host "[protobuf] repo: $RepoDir"
Write-Host "[protobuf] protoc version: $Version"

Push-Location $RepoDir
try {
  flutter pub global activate protoc_plugin
} finally {
  Pop-Location
}

if (!(Test-Path $Plugin)) {
  throw "protoc-gen-dart not found at $Plugin"
}

New-Item -ItemType Directory -Force -Path $ScriptDir | Out-Null
Invoke-WebRequest $Url -OutFile $ZipPath
if (Test-Path $ProtocDir) {
  Remove-Item $ProtocDir -Recurse -Force
}
Expand-Archive $ZipPath -DestinationPath $ProtocDir -Force
& $ProtocBin --version

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Remove-Item (Join-Path $OutDir "*.pb*.dart") -Force -ErrorAction SilentlyContinue

& $ProtocBin `
  "-I$ProtoDir" `
  "--plugin=protoc-gen-dart=$Plugin" `
  "--dart_out=$OutDir" `
  (Join-Path $ProtoDir "flipper.proto") `
  (Join-Path $ProtoDir "storage.proto") `
  (Join-Path $ProtoDir "system.proto") `
  (Join-Path $ProtoDir "application.proto") `
  (Join-Path $ProtoDir "gui.proto") `
  (Join-Path $ProtoDir "gpio.proto") `
  (Join-Path $ProtoDir "property.proto") `
  (Join-Path $ProtoDir "desktop.proto")

@"
library flipperlib_protobuf;

export 'generated/flipper.pb.dart';
export 'generated/storage.pb.dart';
export 'generated/system.pb.dart';
export 'generated/application.pb.dart';
export 'generated/gui.pb.dart';
export 'generated/gpio.pb.dart';
export 'generated/property.pb.dart';
export 'generated/desktop.pb.dart';
"@ | Set-Content $ExportFile -Encoding UTF8

Write-Host "[protobuf] generated into $OutDir"
