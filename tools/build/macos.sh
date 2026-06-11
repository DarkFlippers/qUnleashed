#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="qUnleashed"
FILE_NAME="qunleashed"
VERSION_NAME="${QUNLEASHED_VERSION_NAME:-}"
DIST_DIR="$ROOT_DIR/dist"
BUILD_APP="$ROOT_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
BACKGROUND_SOURCE="$ROOT_DIR/assets/img/bg.jpg"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The macOS DMG can only be built on macOS." >&2
  exit 1
fi

if [[ -z "$VERSION_NAME" ]]; then
  VERSION_NAME="$(sed -nE 's/^version:[[:space:]]*([0-9A-Za-z._-]+).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
  VERSION_NAME="${VERSION_NAME%%+*}"
fi

if [[ -z "$VERSION_NAME" ]]; then
  echo "App version not found. Set QUNLEASHED_VERSION_NAME or pubspec.yaml version." >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND_SOURCE" ]]; then
  echo "DMG background not found: $BACKGROUND_SOURCE" >&2
  exit 1
fi

FLUTTER_BIN="${FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi

if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter executable not found. Set FLUTTER_BIN=/path/to/flutter." >&2
  exit 1
fi

for command_name in hdiutil osascript sips; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required." >&2
    exit 1
  fi
done

mkdir -p "$DIST_DIR"

echo "Using Flutter: $FLUTTER_BIN"
echo "Building macOS release..."
FLUTTER_COMMAND=("$FLUTTER_BIN" build macos --release)
if [[ -n "${QUNLEASHED_FLUTTER_BUILD_ARGS:-}" ]]; then
  read -r -a FLUTTER_BUILD_ARGS <<< "$QUNLEASHED_FLUTTER_BUILD_ARGS"
  FLUTTER_COMMAND+=("${FLUTTER_BUILD_ARGS[@]}")
fi
(cd "$ROOT_DIR" && "${FLUTTER_COMMAND[@]}")

if [[ ! -d "$BUILD_APP" ]]; then
  echo "Expected app bundle not found: $BUILD_APP" >&2
  exit 1
fi

TARGET_ARCH="$(uname -m)"
APP_EXECUTABLE="$BUILD_APP/Contents/MacOS/$APP_NAME"
if command -v lipo >/dev/null 2>&1 && [[ -f "$APP_EXECUTABLE" ]]; then
  APP_ARCHS="$(lipo -archs "$APP_EXECUTABLE" 2>/dev/null || true)"
  if [[ "$APP_ARCHS" == *"arm64"* && "$APP_ARCHS" == *"x86_64"* ]]; then
    TARGET_ARCH="universal"
  elif [[ "$APP_ARCHS" == *"arm64"* ]]; then
    TARGET_ARCH="arm64"
  elif [[ "$APP_ARCHS" == *"x86_64"* ]]; then
    TARGET_ARCH="x64"
  fi
fi

OUT_FILE="$DIST_DIR/${FILE_NAME}_${VERSION_NAME}_macos_${TARGET_ARCH}.dmg"
VOLUME_NAME="$APP_NAME $VERSION_NAME"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${FILE_NAME}-dmg.XXXXXX")"
STAGING_DIR="$TMP_DIR/staging"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
RW_IMAGE="$TMP_DIR/${FILE_NAME}-rw.dmg"
MOUNTED=0

cleanup() {
  if [[ "$MOUNTED" -eq 1 ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ -e "$MOUNT_DIR" ]]; then
  echo "A volume is already mounted at: $MOUNT_DIR" >&2
  echo "Eject it before building the DMG." >&2
  exit 1
fi

mkdir -p "$STAGING_DIR/.background"
cp -R "$BUILD_APP" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Finder does not scale DMG backgrounds, so prepare one matching the window.
sips --setProperty format png --resampleHeightWidth 563 900 "$BACKGROUND_SOURCE" \
  --out "$STAGING_DIR/.background/bg.png" >/dev/null

cat > "$STAGING_DIR/readme.txt" <<'INSTRUCTIONS'
qUnleashed for macOS
====================

qUnleashed uses Apple's official application signing and notarization process.
Temporary certification or notarization issues may occasionally cause macOS to
place the application in quarantine or report that it is damaged.

1. Drag qUnleashed.app to the Applications folder.
2. If macOS prevents the application from opening, open Terminal and run:

   sudo xattr -dr com.apple.quarantine "/Applications/qUnleashed.app"
   open "/Applications/qUnleashed.app"

   Enter your macOS administrator password when prompted. Terminal does not
   display password characters while you type.

3. If Terminal reports "Operation not permitted", grant it Full Disk Access:

   - Open System Settings.
   - Select Privacy & Security.
   - Open Full Disk Access.
   - Unlock the settings or authenticate when requested.
   - Enable Terminal. If it is not listed, click "+" and add:
     /System/Applications/Utilities/Terminal.app
   - Quit and reopen Terminal, then run the commands above again.

Full Disk Access does not grant administrator or sudo privileges. If your
account is not an administrator or sudo is restricted by your organization,
contact the Mac administrator.

The xattr command removes only the quarantine attribute from qUnleashed. It
does not disable Gatekeeper or other macOS security protections system-wide.


qUnleashed для macOS
====================

qUnleashed использует официальный процесс подписи и нотаризации приложений
Apple. Иногда временные сложности с сертификацией или нотаризацией могут
привести к тому, что macOS поместит приложение в карантин или сообщит, что оно
повреждено.

1. Перетащите qUnleashed.app в папку Applications.
2. Если macOS не позволяет открыть приложение, запустите Terminal и выполните:

   sudo xattr -dr com.apple.quarantine "/Applications/qUnleashed.app"
   open "/Applications/qUnleashed.app"

   Когда появится запрос, введите пароль администратора macOS. Во время ввода
   пароля Terminal не отображает символы.

3. Если Terminal сообщает "Operation not permitted", предоставьте ему полный
   доступ к диску:

   - Откройте «Системные настройки».
   - Выберите «Конфиденциальность и безопасность».
   - Откройте «Полный доступ к диску».
   - Разблокируйте настройки или подтвердите действие.
   - Включите Terminal. Если его нет в списке, нажмите «+» и добавьте:
     /System/Applications/Utilities/Terminal.app
   - Полностью закройте и снова откройте Terminal, затем повторите команды.

Полный доступ к диску не предоставляет права администратора или sudo. Если
ваша учетная запись не является администратором или sudo ограничен вашей
организацией, обратитесь к администратору Mac.

Команда xattr удаляет только атрибут карантина с qUnleashed. Она не отключает
Gatekeeper или другие механизмы безопасности macOS для всей системы.
INSTRUCTIONS

echo "Creating DMG..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_IMAGE" >/dev/null

hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  -nobrowse \
  "$RW_IMAGE" >/dev/null
MOUNTED=1

sleep 5
osascript - "$VOLUME_NAME" <<'APPLESCRIPT'
on run (volumeName)
  tell application "Finder"
    tell disk (volumeName as string)
      open
      tell container window
        set current view to icon view
        set toolbar visible to false
        set statusbar visible to false
        set pathbar visible to false
        set bounds to {100, 100, 1000, 663}
      end tell

      set opts to the icon view options of container window
      tell opts
        set icon size to 96
        set text size to 13
        set arrangement to not arranged
      end tell
      set background picture of opts to file ".background:bg.png"

      set position of item "qUnleashed.app" to {210, 270}
      set position of item "Applications" to {690, 270}
      set position of item "readme.txt" to {820, 80}
      close
      open
      delay 3
    end tell
  end tell
end run
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNTED=0

rm -f "$OUT_FILE"
hdiutil convert "$RW_IMAGE" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUT_FILE" >/dev/null

echo "Built macOS DMG:"
echo "$OUT_FILE"
