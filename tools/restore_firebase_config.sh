#!/usr/bin/env bash
set -euo pipefail

restore_secret_file() {
  local secret_name="$1"
  local output_path="$2"
  local secret_value="${!secret_name:-}"

  if [ -z "$secret_value" ]; then
    echo "::error::$secret_name is not configured. Store the base64-encoded Firebase config in GitHub repository secrets."
    exit 1
  fi

  mkdir -p "$(dirname "$output_path")"
  printf '%s' "$secret_value" | base64 --decode > "$output_path"
}

case "${1:-}" in
  android)
    restore_secret_file ANDROID_GOOGLE_SERVICES_JSON_BASE64 android/app/google-services.json
    ;;
  ios)
    restore_secret_file IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 ios/Runner/GoogleService-Info.plist
    ;;
  macos)
    restore_secret_file MACOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 macos/Runner/GoogleService-Info.plist
    ;;
  *)
    echo "Usage: $0 android|ios|macos" >&2
    exit 2
    ;;
esac
