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

export JAVA_HOME="/opt/android-studio/jbr"
export PATH="$JAVA_HOME/bin:$PATH"

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

echo "[DONE] Build and copy completed successfully!"
echo
echo "✅ JAR at: $DEST_DIR/$DEST_FILE"
echo
