#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.gyawun.music"
APP_NAME="GyawunMusic"
VERSION="2.0.16"
BUNDLE_DIR="build/linux/x64/release/bundle"
OLD_BIN="gyawun"
NEW_BIN="gmusic"
MANIFEST="com.gyawun.music.yml"
BUILD_DIR="build-dir"
REPO_DIR="repo"
OUT_FILE="${APP_NAME}-${VERSION}.flatpak"

echo "▶ Building Flutter Linux release…"
flutter build linux --release

echo "▶ Verifying Flutter bundle…"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "ERROR: Flutter bundle not found at $BUNDLE_DIR"
  exit 1
fi

if [[ ! -f "$BUNDLE_DIR/$OLD_BIN" && ! -f "$BUNDLE_DIR/$NEW_BIN" ]]; then
  echo "ERROR: Neither '$OLD_BIN' nor '$NEW_BIN' found in bundle"
  exit 1
fi

if [[ -f "$BUNDLE_DIR/$OLD_BIN" ]]; then
  echo "▶ Renaming binary: $OLD_BIN → $NEW_BIN"
  mv -f "$BUNDLE_DIR/$OLD_BIN" "$BUNDLE_DIR/$NEW_BIN"
fi

chmod +x "$BUNDLE_DIR/$NEW_BIN"

echo "▶ Building Flatpak (clean)…"
flatpak-builder --force-clean "$BUILD_DIR" "$MANIFEST"

echo "▶ Exporting Flatpak repository…"
rm -rf "$REPO_DIR"
flatpak-builder --force-clean --repo="$REPO_DIR" "$BUILD_DIR" "$MANIFEST"

echo "▶ Creating .flatpak bundle…"
flatpak build-bundle \
  "$REPO_DIR" \
  "$OUT_FILE" \
  "$APP_ID" \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo

echo "✔ Done."
echo "✔ Bundle created: $OUT_FILE"
