#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/RuntimeBridges/Desktop"
DEST_DIR="$HOME/Documents/AnymeX/Tools"
DEST_FILE="anymex_desktop_runtime.jar"

echo "=============================="
echo " AnymeX Desktop Bridge Builder"
echo "=============================="
echo

if [[ -d "/opt/android-studio/jbr" ]]; then
    export JAVA_HOME="/opt/android-studio/jbr"
elif [[ -d "$HOME/.gradle/jdks/amazon_com_inc_-21-amd64-linux.2" ]]; then
    export JAVA_HOME="$HOME/.gradle/jdks/amazon_com_inc_-21-amd64-linux.2"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}$PATH"

echo "☕ Java: $(java -version 2>&1 | head -1)"
echo
cd "$PROJECT_DIR"

./gradlew shadowJar

echo
echo "[BUILD] Build successful!"

echo "[COPY] Copying to $DEST_DIR/$DEST_FILE..."
mkdir -p "$DEST_DIR"
cp -f "build/libs/desktop_bridge.jar" "$DEST_DIR/$DEST_FILE"

LOCAL_SHARE_DIR="$HOME/Documents/AnymeX/Runtime"
echo "[COPY] Copying to local runtime share directory: $LOCAL_SHARE_DIR/$DEST_FILE"
mkdir -p "$LOCAL_SHARE_DIR"
cp -f "build/libs/desktop_bridge.jar" "$LOCAL_SHARE_DIR/$DEST_FILE"

APP_DATA_DIR="$HOME/.local/share/com.ryan.anymex/AnymeX/Runtime"
if [[ -d "$HOME/.local/share/com.ryan.anymex" ]]; then
    echo "[COPY] Copying to app data runtime directory: $APP_DATA_DIR/$DEST_FILE"
    mkdir -p "$APP_DATA_DIR"
    cp -f "build/libs/desktop_bridge.jar" "$APP_DATA_DIR/$DEST_FILE"
fi

echo "[DONE] Build and copy completed successfully!"
echo
echo "✅ JAR at: $DEST_DIR/$DEST_FILE"
echo
