#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MagicBorder"
CLI_NAME="MagicBorderCLI"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
INFO_PLIST_SRC="$ROOT_DIR/Sources/MagicBorder/Resources/Info.plist"

VERSION_TAG="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
VERSION="${VERSION_TAG#v}"
if [[ -z "$VERSION" || "$VERSION" == "$VERSION_TAG" && "$VERSION" == "" ]]; then
  VERSION="0.1.0"
fi
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ ! -f "$INFO_PLIST_SRC" ]]; then
  echo "Info.plist not found at $INFO_PLIST_SRC"
  exit 1
fi

echo "Building release..."
swift -C "$ROOT_DIR" build -c release

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -type d \( -name "${APP_NAME}_*.bundle" -o -name "${APP_NAME}.bundle" \) | head -n 1 || true)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
else
  echo "Warning: resource bundle not found in $BUILD_DIR"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist" || \
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist" || \
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Codesigning with identity: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Notarizing with profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$APP_BUNDLE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
fi

echo "Creating archives..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/${APP_NAME}-macos-${VERSION}.zip"
/usr/bin/ditto -c -k "$BUILD_DIR/$CLI_NAME" "$DIST_DIR/${CLI_NAME}-macos-${VERSION}.zip"

if [[ "${CREATE_DMG:-}" == "1" ]]; then
  DMG_PATH="$DIST_DIR/${APP_NAME}-macos-${VERSION}.dmg"
  echo "Creating DMG at $DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"
fi

if [[ "${CREATE_PKG:-}" == "1" ]]; then
  PKG_PATH="$DIST_DIR/${APP_NAME}-macos-${VERSION}.pkg"
  PKG_STAGING="$DIST_DIR/pkg-staging"
  echo "Creating PKG at $PKG_PATH"
  rm -rf "$PKG_STAGING"
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
  (cd "$DIST_DIR" && shasum -a 256 ${CHECKSUM_FILES[@]##*/} > SHA256SUMS.txt)
fi

echo "Done. Artifacts in $DIST_DIR".
