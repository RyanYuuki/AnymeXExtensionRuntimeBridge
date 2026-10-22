#!/bin/sh
# Vendors the prebuilt TorrServerKit.xcframework (a `gomobile bind` build of
# github.com/YouROK/TorrServer's own iOS release asset) for the iOS embedded
# TorrServer controller. Unlike PrepareEmbeddedRuntime.sh's OpenJDK runtime,
# this artifact needs no local build step - it's downloaded, checksum
# verified, and unzipped into place as-is.
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CACHE_DIR="${HOME}/Library/Caches/anymex_extension_bridge/torrserverkit-MatriX.146.1"
FRAMEWORKS_DIR="${SCRIPT_DIR}/anymex_extension_bridge/Frameworks"

VERSION="MatriX.146.1"
XCFRAMEWORK_ZIP="${CACHE_DIR}/TorrServerKit.xcframework.zip"
XCFRAMEWORK_URL="https://github.com/YouROK/TorrServer/releases/download/${VERSION}/TorrServer-ios-TorrServerKit.xcframework.zip"
XCFRAMEWORK_SHA256="20d0f1e705f72cc87209330570b058eb6368a8800a4ad7cc694802b11b9a2700"

if [ -d "${FRAMEWORKS_DIR}/TorrServerKit.xcframework" ]; then
  exit 0
fi

mkdir -p "${CACHE_DIR}" "${FRAMEWORKS_DIR}"

if [ -f "${XCFRAMEWORK_ZIP}" ]; then
  actual="$(/usr/bin/shasum -a 256 "${XCFRAMEWORK_ZIP}" | /usr/bin/cut -d ' ' -f 1)"
  [ "${actual}" != "${XCFRAMEWORK_SHA256}" ] && rm -f "${XCFRAMEWORK_ZIP}"
fi

if [ ! -f "${XCFRAMEWORK_ZIP}" ]; then
  temporary="${XCFRAMEWORK_ZIP}.download"
  rm -f "${temporary}"
  /usr/bin/curl --fail --location --retry 3 --output "${temporary}" "${XCFRAMEWORK_URL}"
  actual="$(/usr/bin/shasum -a 256 "${temporary}" | /usr/bin/cut -d ' ' -f 1)"
  if [ "${actual}" != "${XCFRAMEWORK_SHA256}" ]; then
    rm -f "${temporary}"
    echo "SHA-256 mismatch for ${XCFRAMEWORK_URL}" >&2
    exit 1
  fi
  mv "${temporary}" "${XCFRAMEWORK_ZIP}"
fi

/usr/bin/unzip -q -o "${XCFRAMEWORK_ZIP}" -d "${FRAMEWORKS_DIR}"

test -d "${FRAMEWORKS_DIR}/TorrServerKit.xcframework/ios-arm64/TorrServerKit.framework"
echo "Prepared TorrServerKit.xcframework for anymex_extension_bridge"
