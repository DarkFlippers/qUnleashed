#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$LIB_DIR/../.." && pwd)"

VERSION="${PROTOC_VERSION:-34.1}"
ARCHIVE_NAME="protoc-${VERSION}-osx-universal_binary.zip"
ZIP_PATH="$SCRIPT_DIR/protoc.zip"
PROTOC_DIR="$SCRIPT_DIR/protoc"
PROTOC_BIN="$PROTOC_DIR/bin/protoc"
PROTO_DIR="$LIB_DIR/proto/flipperzero"
OUT_DIR="$LIB_DIR/generated"
EXPORT_FILE="$LIB_DIR/protobuf.dart"
PLUGIN_PATH="${HOME}/.pub-cache/bin/protoc-gen-dart"

echo "[protobuf] repo: $REPO_DIR"
echo "[protobuf] protoc version: $VERSION"

cd "$REPO_DIR"
flutter pub global activate protoc_plugin

if [[ ! -x "$PLUGIN_PATH" ]]; then
  echo "[protobuf] protoc-gen-dart not found at $PLUGIN_PATH" >&2
  exit 1
fi

mkdir -p "$SCRIPT_DIR"
curl -L "https://github.com/protocolbuffers/protobuf/releases/download/v${VERSION}/${ARCHIVE_NAME}" -o "$ZIP_PATH"
rm -rf "$PROTOC_DIR"
unzip -oq "$ZIP_PATH" -d "$PROTOC_DIR"
"$PROTOC_BIN" --version

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.pb*.dart

"$PROTOC_BIN" \
  "-I$PROTO_DIR" \
  "--plugin=protoc-gen-dart=$PLUGIN_PATH" \
  "--dart_out=$OUT_DIR" \
  "$PROTO_DIR/flipper.proto" \
  "$PROTO_DIR/storage.proto" \
  "$PROTO_DIR/system.proto" \
  "$PROTO_DIR/application.proto" \
  "$PROTO_DIR/gui.proto" \
  "$PROTO_DIR/gpio.proto" \
  "$PROTO_DIR/property.proto" \
  "$PROTO_DIR/desktop.proto"

cat > "$EXPORT_FILE" <<'EOF'
library flipperlib_protobuf;

export 'generated/flipper.pb.dart';
export 'generated/storage.pb.dart';
export 'generated/system.pb.dart';
export 'generated/application.pb.dart';
export 'generated/gui.pb.dart';
export 'generated/gpio.pb.dart';
export 'generated/property.pb.dart';
export 'generated/desktop.pb.dart';
EOF

echo "[protobuf] generated into $OUT_DIR"
