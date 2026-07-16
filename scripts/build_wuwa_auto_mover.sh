#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="${ROOT_DIR}"
BUILD_DIR="${ROOT_DIR}/build"
APP_NAME="WuwaAutoMover"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
APP_VERSION="${WUWA_VERSION:-}"
BUILD_NUMBER="${WUWA_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${WUWA_CODESIGN_IDENTITY:--}"
RELEASE_BUILD_DIR="$(swift build --package-path "${PACKAGE_DIR}" -c release --show-bin-path)"

if [[ -n "${APP_VERSION}" && ! "${APP_VERSION}" =~ ^[0-9A-Za-z.-]+$ ]]; then
  echo "Invalid WUWA_VERSION: ${APP_VERSION}" >&2
  exit 1
fi

if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "WUWA_BUILD_NUMBER must contain digits only." >&2
  exit 1
fi

swift build \
  --package-path "${PACKAGE_DIR}" \
  -c release \
  --product WuwaAutoMoverGUI

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${FRAMEWORKS_DIR}" "${RESOURCES_DIR}"
cp "${PACKAGE_DIR}/Info.plist" "${CONTENTS_DIR}/Info.plist"

if [[ -n "${APP_VERSION}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

cp "${RELEASE_BUILD_DIR}/WuwaAutoMoverGUI" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

SPARKLE_FRAMEWORK="$(find "${PACKAGE_DIR}/.build/artifacts/sparkle" -type d -name Sparkle.framework -print -quit)"
if [[ -z "${SPARKLE_FRAMEWORK}" ]]; then
  echo "Sparkle.framework was not found in SwiftPM artifacts." >&2
  exit 1
fi
ditto "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/Sparkle.framework"

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  codesign --force --sign - --deep "${APP_DIR}"
else
  codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" --deep "${APP_DIR}"
fi
codesign --verify --deep --strict "${APP_DIR}"

case "${RELEASE_BUILD_DIR}" in
  "${PACKAGE_DIR}/.build/"*) ;;
  *)
    echo "Refusing to remove unexpected release directory: ${RELEASE_BUILD_DIR}" >&2
    exit 1
    ;;
esac
rm -rf "${RELEASE_BUILD_DIR}" "${PACKAGE_DIR}/.build/release"

echo "Built ${APP_DIR}"
echo "Removed Swift release artifacts from ${RELEASE_BUILD_DIR}"
