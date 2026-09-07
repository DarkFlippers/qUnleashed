#!/usr/bin/env bash
# Writes a placeholder firebase_options.dart so `flutter analyze` and
# `flutter test` can run on a checkout that has no Firebase secrets — a pull
# request from a fork, or a clone by a contributor.
#
# This is deliberately NOT part of restore_firebase_config.sh: a release must
# keep failing loudly when the real configuration is missing, and must never
# fall back to a stub that ships an app whose push notifications throw.
set -Eeuo pipefail

TARGET="lib/services/notifications/firebase_options.dart"

if [ -s "$TARGET" ]; then
  echo "$TARGET already exists, leaving it alone."
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"
cat > "$TARGET" <<'DART'
// GENERATED PLACEHOLDER - not the real Firebase configuration.
//
// Written by .github/scripts/stub_firebase_config.sh so static analysis and
// tests can run without repository secrets. Release builds restore the real
// file from a secret instead; see .github/scripts/restore_firebase_config.sh.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform => throw UnsupportedError(
    'This build carries no Firebase configuration.',
  );
}
DART

echo "Wrote a placeholder $TARGET."
