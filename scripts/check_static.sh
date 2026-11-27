#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Checking localization key parity and plist validity..."
python3 - <<'PY'
import pathlib
import plistlib
import re
import sys

def load_strings_keys(path: str) -> set[str]:
    text = pathlib.Path(path).read_text(encoding="utf-8")
    return set(re.findall(r'^"([^"]+)"\s*=', text, re.MULTILINE))

pairs = [
    (
        "Sources/MagicBorder/Resources/en.lproj/Localizable.strings",
        "Sources/MagicBorder/Resources/zh-Hans.lproj/Localizable.strings",
    ),
    (
        "Sources/MagicBorder/Resources/en.lproj/InfoPlist.strings",
        "Sources/MagicBorder/Resources/zh-Hans.lproj/InfoPlist.strings",
    ),
]

failed = False
for en_path, zh_path in pairs:
    en_keys = load_strings_keys(en_path)
    zh_keys = load_strings_keys(zh_path)
    missing_zh = sorted(en_keys - zh_keys)
    missing_en = sorted(zh_keys - en_keys)
    if missing_zh:
        print(f"ERROR: Keys in {en_path} missing from {zh_path}: {missing_zh}", file=sys.stderr)
        failed = True
    if missing_en:
        print(f"ERROR: Keys in {zh_path} missing from {en_path}: {missing_en}", file=sys.stderr)
        failed = True
    print(f"OK {en_path} <-> {zh_path}: {len(en_keys)} keys match")

info_path = pathlib.Path("Sources/MagicBorder/Resources/Info.plist")
with info_path.open("rb") as f:
    info = plistlib.load(f)

required_info_keys = [
    "CFBundleIdentifier",
    "CFBundleIconFile",
    "CFBundleIconName",
    "LSMinimumSystemVersion",
    "NSLocalNetworkUsageDescription",
    "NSScreenCaptureUsageDescription",
    "NSPrincipalClass",
    "NSHighResolutionCapable",
]
for key in required_info_keys:
    if key not in info:
        print(f"ERROR: Missing required key {key!r} in {info_path}", file=sys.stderr)
        failed = True
print(f"OK {info_path} parsed with all required keys")

entitlements_path = pathlib.Path("Sources/MagicBorder/Resources/MagicBorder.entitlements")
with entitlements_path.open("rb") as f:
    entitlements = plistlib.load(f)
if not isinstance(entitlements, dict):
    print(f"ERROR: Invalid dictionary in {entitlements_path}", file=sys.stderr)
    failed = True
print(f"OK {entitlements_path} parsed")

if failed:
    sys.exit(1)
PY

echo "Checking architecture guardrails in Sources/..."
if grep -rn "@unchecked Sendable" Sources/; then
  echo "ERROR: @unchecked Sendable is forbidden in Sources/" >&2
  exit 1
fi

if grep -rnE "static (let|var) shared\b" Sources/; then
  echo "ERROR: Custom .shared singletons are forbidden in Sources/" >&2
  exit 1
fi

echo "All static checks passed."
