#!/bin/sh
# Builds the embedded OpenJDK Zero runtime for iOS.
#
# Adapted from https://github.com/kodjodevf/m_extension_server
# (ios/PrepareEmbeddedRuntime.sh). Differences:
#   * no MExtensionServer JAR — dartotsu backends load their own fat JARs at
#     runtime; the only JAR staged here is the small `embedded-bridge` shim
#     (built from runtimeManager/libraries/commonDesktopLib) that the native
#     layer calls into.
#   * the pinned OpenJDK Zero xcframework + java_bundle artifacts are reused
#     verbatim (same URLs / SHA-256) — "do exactly as they do".
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CACHE_DIR="${HOME}/Library/Caches/anymex_extension_bridge/embedded-openjdk-ios13-v16"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dartotsu-embedded-zero.XXXXXX")"
FRAMEWORKS_DIR="${SCRIPT_DIR}/anymex_extension_bridge/Frameworks"
RUNTIME_DIR="${SCRIPT_DIR}/anymex_extension_bridge/Sources/anymex_extension_bridge/Runtime"
trap 'rm -rf "${WORK_DIR}"' EXIT

# --- the embedded-bridge shim JAR -------------------------------------------
# Built by: (cd runtimeManager && ./gradlew buildEmbeddedBridge)
#   -> runtimeManager/libraries/commonDesktopLib/build/libs/embedded-bridge.jar
# .github/workflows/build.yml stages it into every `latest` release. That tag
# is rolling (deleted + recreated on every CI run), so BRIDGE_JAR_SHA256 can
# go stale if embedded-bridge.jar's contents ever change - re-download and
# re-hash it then. A future improvement is publishing it under an immutable
# `ios-runtime-v*` tag instead, so this can stop needing manual re-pinning.
# To skip the download entirely, drop the jar by hand at
# ios/anymex_extension_bridge/Sources/anymex_extension_bridge/Runtime/embedded-bridge.jar.
BRIDGE_JAR="${CACHE_DIR}/embedded-bridge.jar"
BRIDGE_JAR_URL="https://github.com/aayush2622/DartotsuExtensionBridge/releases/download/latest/embedded-bridge.jar"
BRIDGE_JAR_SHA256="f8ed258835def15e4a3f4e1274898aa3d643f827ad97cba0a8425544942cb0d8"

OPENJDK_ZIP="${CACHE_DIR}/OpenJDK.xcframework.zip"
JAVA_BUNDLE_ZIP="${CACHE_DIR}/java_bundle-device.zip"

OPENJDK_URL="https://github.com/1Selxo/Mangatan/releases/download/embedded-openjdk-ios13-v16/OpenJDK.xcframework.zip"
OPENJDK_SHA256="f21681caae40e508647e7f18c9082f27fa9aa67ee7f1376725eae528fa2d38cb"
JAVA_BUNDLE_URL="https://github.com/1Selxo/Mangatan/releases/download/embedded-openjdk-ios13-v16/java_bundle-device.zip"
JAVA_BUNDLE_SHA256="15369b9bb9dfdd400c18c56b30e2f6cf316b81d4e0bae5ddd6b1fe72355c4b0b"

if [ -d "${FRAMEWORKS_DIR}/OpenJDKRuntime.xcframework" ] &&
   [ -f "${RUNTIME_DIR}/embedded-bridge.jar" ]; then
  exit 0
fi

mkdir -p "${CACHE_DIR}"

download_verified() {
  url="$1"
  destination="$2"
  expected="$3"
  if [ -f "${destination}" ]; then
    actual="$(/usr/bin/shasum -a 256 "${destination}" | /usr/bin/cut -d ' ' -f 1)"
    [ "${actual}" = "${expected}" ] && return
    rm -f "${destination}"
  fi
  temporary="${destination}.download"
  rm -f "${temporary}"
  /usr/bin/curl --fail --location --retry 3 --output "${temporary}" "${url}"
  actual="$(/usr/bin/shasum -a 256 "${temporary}" | /usr/bin/cut -d ' ' -f 1)"
  if [ "${actual}" != "${expected}" ]; then
    rm -f "${temporary}"
    echo "SHA-256 mismatch for ${url}" >&2
    exit 1
  fi
  mv "${temporary}" "${destination}"
}

# The shim JAR may be staged by hand; only fetch it when it isn't there.
if [ ! -f "${RUNTIME_DIR}/embedded-bridge.jar" ] && [ ! -f "${BRIDGE_JAR}" ]; then
  download_verified "${BRIDGE_JAR_URL}" "${BRIDGE_JAR}" "${BRIDGE_JAR_SHA256}"
fi
download_verified "${OPENJDK_URL}" "${OPENJDK_ZIP}" "${OPENJDK_SHA256}"
download_verified "${JAVA_BUNDLE_URL}" "${JAVA_BUNDLE_ZIP}" "${JAVA_BUNDLE_SHA256}"

JAVA_HOME_EFFECTIVE="${JAVA_HOME:-}"
if [ ! -x "${JAVA_HOME_EFFECTIVE}/bin/javac" ]; then
  JAVA_HOME_EFFECTIVE="$(/usr/libexec/java_home -v 21)"
fi

mkdir -p "${WORK_DIR}/framework" "${WORK_DIR}/java-bundle"
/usr/bin/unzip -q "${OPENJDK_ZIP}" -d "${WORK_DIR}/framework"
/usr/bin/unzip -q "${JAVA_BUNDLE_ZIP}" -d "${WORK_DIR}/java-bundle"

STATIC_LIBRARY="$(/usr/bin/find "${WORK_DIR}/framework" -type f -name libdevice.a -print -quit)"
HEADERS_DIR="$(/usr/bin/find "${WORK_DIR}/framework" -type d -name Headers -print -quit)"
MODULES="$(/usr/bin/find "${WORK_DIR}/java-bundle" -type f -path '*/lib/modules' -print -quit)"
JAVA_ROOT="$(/usr/bin/dirname "$(/usr/bin/dirname "${MODULES}")")"
if [ -z "${STATIC_LIBRARY}" ] || [ -z "${HEADERS_DIR}" ] ||
   [ ! -f "${JAVA_ROOT}/conf/security/java.security" ]; then
  echo "The pinned OpenJDK runtime archive is incomplete" >&2
  exit 1
fi

SHIM_CLASSES="${WORK_DIR}/logging-shim-classes"
mkdir -p "${SHIM_CLASSES}"
"${JAVA_HOME_EFFECTIVE}/bin/javac" \
  --patch-module "java.logging=${SCRIPT_DIR}/RuntimeSources/ios_jul_shim" \
  -d "${SHIM_CLASSES}" \
  "${SCRIPT_DIR}/RuntimeSources/ios_jul_shim/java/util/logging/Level.java" \
  "${SCRIPT_DIR}/RuntimeSources/ios_jul_shim/java/util/logging/Logger.java"
"${JAVA_HOME_EFFECTIVE}/bin/jar" --create \
  --file "${WORK_DIR}/java-logging-shim.jar" \
  -C "${SHIM_CLASSES}" .

DEVICE_FRAMEWORK="${WORK_DIR}/device/OpenJDKRuntime.framework"
mkdir -p "${DEVICE_FRAMEWORK}/Headers" "${DEVICE_FRAMEWORK}/lib/lib"
/usr/bin/ditto "${HEADERS_DIR}" "${DEVICE_FRAMEWORK}/Headers"
/bin/cp "${SCRIPT_DIR}/RuntimeSources/OpenJDKRuntime-Info.plist" "${DEVICE_FRAMEWORK}/Info.plist"
/bin/cp "${JAVA_ROOT}/lib/modules" "${DEVICE_FRAMEWORK}/lib/lib/modules"
/bin/cp "${JAVA_ROOT}/lib/tzdb.dat" "${DEVICE_FRAMEWORK}/lib/lib/tzdb.dat"
/usr/bin/ditto "${JAVA_ROOT}/lib/security" "${DEVICE_FRAMEWORK}/lib/lib/security"
/usr/bin/ditto "${JAVA_ROOT}/conf" "${DEVICE_FRAMEWORK}/lib/conf"

DEVICE_SDK="$(/usr/bin/xcrun --sdk iphoneos --show-sdk-path)"
/usr/bin/xcrun --sdk iphoneos clang++ \
  -target arm64-apple-ios13.0 \
  -isysroot "${DEVICE_SDK}" \
  -dynamiclib \
  -Wl,-all_load \
  "${STATIC_LIBRARY}" \
  "${SCRIPT_DIR}/RuntimeSources/openjdk_runtime_exports.cpp" \
  -Wl,-install_name,@rpath/OpenJDKRuntime.framework/OpenJDKRuntime \
  -Wl,-compatibility_version,1.0.0 \
  -Wl,-current_version,1.0.0 \
  -lz \
  -framework Foundation \
  -framework CoreFoundation \
  -o "${DEVICE_FRAMEWORK}/OpenJDKRuntime"

SIMULATOR_FRAMEWORK="${WORK_DIR}/simulator/OpenJDKRuntime.framework"
mkdir -p "${SIMULATOR_FRAMEWORK}"
/bin/cp "${SCRIPT_DIR}/RuntimeSources/OpenJDKRuntime-Info.plist" "${SIMULATOR_FRAMEWORK}/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleSupportedPlatforms:0 iPhoneSimulator' "${SIMULATOR_FRAMEWORK}/Info.plist"
SIMULATOR_SDK="$(/usr/bin/xcrun --sdk iphonesimulator --show-sdk-path)"
for arch in arm64 x86_64; do
  /usr/bin/xcrun --sdk iphonesimulator clang++ \
    -target "${arch}-apple-ios13.0-simulator" \
    -isysroot "${SIMULATOR_SDK}" \
    -dynamiclib \
    "${SCRIPT_DIR}/RuntimeSources/openjdk_simulator_stub.cpp" \
    -Wl,-install_name,@rpath/OpenJDKRuntime.framework/OpenJDKRuntime \
    -o "${WORK_DIR}/OpenJDKRuntime-${arch}"
done
/usr/bin/lipo -create \
  "${WORK_DIR}/OpenJDKRuntime-arm64" \
  "${WORK_DIR}/OpenJDKRuntime-x86_64" \
  -output "${SIMULATOR_FRAMEWORK}/OpenJDKRuntime"

rm -rf "${FRAMEWORKS_DIR}/OpenJDKRuntime.xcframework"
mkdir -p "${FRAMEWORKS_DIR}" "${RUNTIME_DIR}/lib/security"
/usr/bin/xcodebuild -create-xcframework \
  -framework "${DEVICE_FRAMEWORK}" \
  -framework "${SIMULATOR_FRAMEWORK}" \
  -output "${FRAMEWORKS_DIR}/OpenJDKRuntime.xcframework"
if [ -f "${BRIDGE_JAR}" ]; then
  /bin/cp "${BRIDGE_JAR}" "${RUNTIME_DIR}/embedded-bridge.jar"
fi
/bin/cp "${WORK_DIR}/java-logging-shim.jar" "${RUNTIME_DIR}/java-logging-shim.jar"
/bin/cp "${JAVA_ROOT}/lib/security/cacerts" "${RUNTIME_DIR}/lib/security/cacerts"
/bin/cp "${JAVA_ROOT}/release" "${RUNTIME_DIR}/release"
/bin/cp "${SCRIPT_DIR}/RuntimeSources/THIRD_PARTY_NOTICES.md" \
  "${RUNTIME_DIR}/THIRD_PARTY_NOTICES.md"

test -x "${FRAMEWORKS_DIR}/OpenJDKRuntime.xcframework/ios-arm64/OpenJDKRuntime.framework/OpenJDKRuntime"
test -f "${RUNTIME_DIR}/embedded-bridge.jar"
echo "Prepared embedded OpenJDK Zero runtime for anymex_extension_bridge"
