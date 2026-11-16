#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
repo="$PWD"
python="${BOSECTL_PYTHON:-$repo/python/.venv/bin/python}"
if [[ ! -x "$python" ]] || ! "$python" -c 'import IOBluetooth, objc'; then
    echo "Set up the macOS backend with make python-setup, then run make macos-app again." >&2
    echo "You can also set BOSECTL_PYTHON to a Python with PyObjC and IOBluetooth installed." >&2
    exit 1
fi
python="$("$python" -c 'import os, sys; print(os.path.abspath(sys.executable))')"

mkdir -p dist build
staging="$(mktemp -d "$repo/dist/.bose-control.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/BoseControl.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" build/swift-module-cache

target="$(uname -m)-apple-macosx14.0"
xcrun swiftc -parse-as-library -O -target "$target" \
    -module-cache-path "$repo/build/swift-module-cache" \
    macos/Headphones.swift macos/BoseControl.swift -o "$contents/MacOS/BoseControl"

cp macos/Info.plist "$contents/Info.plist"
plutil -insert BoseControlPython -string "$python" "$contents/Info.plist"
cp macos/AppIcon.icns macos/bridge.py LICENSE "$contents/Resources/"
"$python" - "$contents/Resources" <<'PYTHON'
import shutil
import sys
from pathlib import Path

shutil.copytree("python/pybmap", Path(sys.argv[1]) / "pybmap",
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
PYTHON
PYTHONDONTWRITEBYTECODE=1 "$python" "$contents/Resources/bridge.py" '{"check":true}' |
    "$python" -c 'import json, sys; sys.exit(0 if json.load(sys.stdin).get("ready") else 1)'
codesign --force --sign - "$app"
codesign --verify --strict "$app"

output="$repo/dist/BoseControl.app"
if [[ -d "$output" ]]; then
    mv "$output" "$staging/previous.app"
fi
if ! mv "$app" "$output"; then
    if [[ -d "$staging/previous.app" ]]; then
        mv "$staging/previous.app" "$output"
    fi
    exit 1
fi
echo "$output"
