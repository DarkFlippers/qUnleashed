#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  ./tools/downgrade_update_cache_versions.sh unlshd
  ./tools/downgrade_update_cache_versions.sh ofw
  ./tools/downgrade_update_cache_versions.sh both

Downgrades release versions in qUnleashed update cache by one numeric step.
EOF
}

target="${1:-}"
case "$target" in
  unlshd)
    files=("/Users/apfx/Documents/qUnleashed/updates/unlshd.json")
    ;;
  ofw)
    files=("/Users/apfx/Documents/qUnleashed/updates/ofw.json")
    ;;
  both)
    files=(
      "/Users/apfx/Documents/qUnleashed/updates/unlshd.json"
      "/Users/apfx/Documents/qUnleashed/updates/ofw.json"
    )
    ;;
  *)
    usage
    exit 2
    ;;
esac

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing cache file: $file" >&2
    exit 1
  fi
done

python3 - "${files[@]}" <<'PY'
import json
import re
import sys
from pathlib import Path

FILES = [Path(raw) for raw in sys.argv[1:]]


def downgrade_version(version: str) -> str:
    match = re.search(r"(\d+)(?!.*\d)", version)
    if not match:
        raise ValueError(f"version has no numeric part: {version}")

    number = match.group(1)
    value = int(number)
    if value <= 0:
        raise ValueError(f"last numeric part is already zero: {version}")

    downgraded = str(value - 1).zfill(len(number))
    return f"{version[:match.start()]}{downgraded}{version[match.end():]}"


def release_latest(data: dict) -> dict:
    for channel in data.get("channels", []):
        if channel.get("id") == "release":
            versions = channel.get("versions") or []
            if not versions:
                raise ValueError("release channel has no versions")
            return versions[0]
    raise ValueError("release channel not found")


for path in FILES:
    data = json.loads(path.read_text(encoding="utf-8"))
    latest = release_latest(data)
    old = latest.get("version")
    if not isinstance(old, str):
        raise ValueError(f"{path}: release latest version is not a string")

    new = downgrade_version(old)

    latest["version"] = new
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{path}: {old} -> {new}")
PY
