#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MagicBorder"
CLI_NAME="MagicBorderCLI"
DIST_DIR="$ROOT_DIR/dist"
INFO_PLIST_SRC="$ROOT_DIR/Sources/MagicBorder/Resources/Info.plist"
ENTITLEMENTS_SRC="$ROOT_DIR/Sources/MagicBorder/Resources/MagicBorder.entitlements"
ASSETS_SRC="$ROOT_DIR/Sources/MagicBorder/Resources/Assets.xcassets"

RAW_VERSION="${RELEASE_VERSION:-}"
if [[ -z "$RAW_VERSION" ]]; then
  RAW_VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
fi
VERSION="${RAW_VERSION#v}"
if [[ -z "$VERSION" ]]; then
  VERSION="0.1.0"
fi
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
ARCH_MODE="${ARCH_MODE:-universal}"

if [[ ! -f "$INFO_PLIST_SRC" ]]; then
  echo "Info.plist not found at $INFO_PLIST_SRC" >&2
  exit 1
fi

ARCH_FLAGS=()
case "$ARCH_MODE" in
  universal)
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
    ;;
  native)
    ARCH_FLAGS=()
    ;;
  *)
    echo "Unsupported ARCH_MODE='$ARCH_MODE' (expected 'universal' or 'native')" >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Building release ($ARCH_MODE) version $VERSION ($BUILD_NUMBER)..."
swift build --package-path "$ROOT_DIR" -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} -Xswiftc -warnings-as-errors
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

if [[ -d "$ASSETS_SRC" ]]; then
  echo "Compiling asset catalog into AppIcon.icns and Assets.car..."
  xcrun actool "$ASSETS_SRC" \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$TMP_DIR/partial-info.plist" >/dev/null
  if [[ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
    echo "ERROR: actool did not produce AppIcon.icns" >&2
    exit 1
  fi
fi

for locale in en zh-Hans; do
  LOCALE_STRINGS="$ROOT_DIR/Sources/MagicBorder/Resources/${locale}.lproj/InfoPlist.strings"
  if [[ -f "$LOCALE_STRINGS" ]]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/${locale}.lproj"
    cp "$LOCALE_STRINGS" "$APP_BUNDLE/Contents/Resources/${locale}.lproj/InfoPlist.strings"
  fi
done

RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -type d \( -name "${APP_NAME}_*.bundle" -o -name "${APP_NAME}.bundle" \) | head -n 1 || true)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
else
  echo "Warning: resource bundle not found in $BUILD_DIR" >&2
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist" || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist" || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Codesigning with identity: $SIGN_IDENTITY"
  for bundle in "$APP_BUNDLE/Contents/Resources"/*.bundle; do
    if [[ -d "$bundle" ]]; then
      codesign --force --timestamp --sign "$SIGN_IDENTITY" "$bundle"
    fi
  done
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS_SRC" \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$BUILD_DIR/$CLI_NAME"
else
  echo "Ad-hoc codesigning $APP_BUNDLE..."
  codesign --force --sign - "$APP_BUNDLE"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Notarizing with profile: $NOTARY_PROFILE"
  NOTARY_ZIP="$TMP_DIR/${APP_NAME}-notary.zip"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
fi

echo "Creating archives..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/${APP_NAME}-macos-${VERSION}.zip"
/usr/bin/ditto -c -k "$BUILD_DIR/$CLI_NAME" "$DIST_DIR/${CLI_NAME}-macos-${VERSION}.zip"

if [[ "${CREATE_DMG:-}" == "1" ]]; then
  DMG_PATH="$DIST_DIR/${APP_NAME}-macos-${VERSION}.dmg"
  DMG_STAGING="$TMP_DIR/dmg-staging"
  echo "Creating DMG at $DMG_PATH"
  mkdir -p "$DMG_STAGING"
  cp -R "$APP_BUNDLE" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
fi

if [[ "${CREATE_PKG:-}" == "1" ]]; then
  PKG_PATH="$DIST_DIR/${APP_NAME}-macos-${VERSION}.pkg"
  PKG_STAGING="$TMP_DIR/pkg-staging"
  echo "Creating PKG at $PKG_PATH"
  mkdir -p "$PKG_STAGING/Applications"
  cp -R "$APP_BUNDLE" "$PKG_STAGING/Applications/"
  if [[ -n "${PKG_SIGN_IDENTITY:-}" ]]; then
    pkgbuild --identifier "com.tinnci.MagicBorder" --version "$VERSION" --install-location "/Applications" --root "$PKG_STAGING" --sign "$PKG_SIGN_IDENTITY" "$PKG_PATH"
  else
    pkgbuild --identifier "com.tinnci.MagicBorder" --version "$VERSION" --install-location "/Applications" --root "$PKG_STAGING" "$PKG_PATH"
  fi
fi

shopt -s nullglob
CHECKSUM_FILES=("$DIST_DIR"/*.zip "$DIST_DIR"/*.dmg "$DIST_DIR"/*.pkg)
shopt -u nullglob
if [[ ${#CHECKSUM_FILES[@]} -gt 0 ]]; then
  (cd "$DIST_DIR" && shasum -a 256 "${CHECKSUM_FILES[@]##*/}" > SHA256SUMS.txt)
fi

echo "Done. Artifacts in $DIST_DIR:"
ls -lh "$DIST_DIR"
