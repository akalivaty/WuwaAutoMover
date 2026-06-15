#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="${ROOT_DIR}"
BUILD_DIR="${ROOT_DIR}/build"
APP_NAME="WuwaAutoMover"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

swift build \
  --package-path "${PACKAGE_DIR}" \
  -c release \
  --product wuwa-auto-mover

swift build \
  --package-path "${PACKAGE_DIR}" \
  -c release \
  --product WuwaAutoMoverGUI

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${PACKAGE_DIR}/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${PACKAGE_DIR}/.build/release/WuwaAutoMoverGUI" "${MACOS_DIR}/${APP_NAME}"
cp "${PACKAGE_DIR}/.build/release/wuwa-auto-mover" "${BUILD_DIR}/wuwa-auto-mover"
cp "${PACKAGE_DIR}/.build/release/wuwa-auto-mover" "${MACOS_DIR}/wuwa-auto-mover"
chmod +x "${MACOS_DIR}/${APP_NAME}" "${MACOS_DIR}/wuwa-auto-mover" "${BUILD_DIR}/wuwa-auto-mover"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --deep "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "Built ${APP_DIR}"
echo "Built ${BUILD_DIR}/wuwa-auto-mover"
