#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APP_NAME="WuwaAutoMover"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
VERSION="${1:-}"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Missing ${APP_DIR}. Run ./scripts/build_wuwa_auto_mover.sh first." >&2
  exit 1
fi

if [[ -z "${VERSION}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_DIR}/Contents/Info.plist")"
fi

if [[ ! "${VERSION}" =~ ^[0-9A-Za-z.-]+$ ]]; then
  echo "Invalid DMG version: ${VERSION}" >&2
  exit 1
fi

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
STAGING_DIR="${BUILD_DIR}/dmg-root"

rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

ditto "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
cp "${ROOT_DIR}/packaging/dmg/README.txt" "${STAGING_DIR}/README.txt"

hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${DMG_PATH}"

hdiutil verify "${DMG_PATH}"
rm -rf "${STAGING_DIR}"

echo "Built ${DMG_PATH}"
shasum -a 256 "${DMG_PATH}"
