#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================="
echo " AnymeX Runtime Host Builder"
echo "=============================="
echo

echo "Script directory: $SCRIPT_DIR"
echo

if [[ -d "/opt/android-studio/jbr" ]]; then
    export JAVA_HOME="/opt/android-studio/jbr"
elif [[ -d "$HOME/.gradle/jdks/amazon_com_inc_-21-amd64-linux.2" ]]; then
    export JAVA_HOME="$HOME/.gradle/jdks/amazon_com_inc_-21-amd64-linux.2"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}$PATH"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools:$PATH"

echo "☕ Java: $(java -version 2>&1 | head -1)"
echo "📱 Android SDK: $ANDROID_HOME"
echo

cd "$SCRIPT_DIR"

echo "Running Gradle Release Build..."
echo

./gradlew assembleRelease

echo
echo "Gradle build finished."
echo

echo "Searching for APK..."

APK_PATH="$(find app/build/outputs/apk/release -name "*.apk" | head -1)"

if [[ -z "$APK_PATH" ]]; then
    echo "❌ APK NOT FOUND"
    exit 1
fi

echo "APK Found:"
echo "$APK_PATH"
echo

FINAL_APK="$SCRIPT_DIR/anymex_runtime_host.apk"

cp -f "$APK_PATH" "$FINAL_APK"

echo "APK Copied to:"
echo "$FINAL_APK"
echo

echo "Checking ADB..."

if ! command -v adb &>/dev/null; then
    echo "❌ ADB NOT FOUND IN PATH"
    echo "Install platform-tools or add to PATH"
    exit 1
fi

echo "Listing devices..."
adb devices
echo

DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"

if [[ -z "$DEVICE" ]]; then
    echo "⚠️  No device connected — skipping ADB push"
    echo
    echo "✅ BUILD DONE (APK at: $FINAL_APK)"
    exit 0
fi

echo "Device Found: $DEVICE"
echo

echo "Creating folder on device..."
adb -s "$DEVICE" shell mkdir -p /sdcard/AnymeX/

echo "Pushing APK..."
adb -s "$DEVICE" push "$FINAL_APK" /sdcard/AnymeX/

echo
echo "✅ DONE SUCCESSFULLY"
echo
