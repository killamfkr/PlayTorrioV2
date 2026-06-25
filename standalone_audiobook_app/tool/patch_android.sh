#!/usr/bin/env bash
# Apply Android manifest + network config after `flutter create .`
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cp "$ROOT/tool/android/AndroidManifest.xml" "$ROOT/android/app/src/main/AndroidManifest.xml"
echo "Patched AndroidManifest.xml for audiobook app"
