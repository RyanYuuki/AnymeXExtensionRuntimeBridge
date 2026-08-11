#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$SCRIPT_DIR/RuntimeBridges/Desktop"
OUTPUT_DIR="$SCRIPT_DIR/output"
TEAVM_CLI_VERSION="0.10.2"

echo "======================================="
echo " Building iOS WASM Extension Runtime Host"
echo "======================================="

mkdir -p "$OUTPUT_DIR"

# 1. Build Desktop Shadow JAR (Contains all classes, stubs, and dependencies)
echo "📦 Step 1: Compiling Kotlin bridge shadow JAR..."
(cd "$DESKTOP_DIR" && ./gradlew shadowJar)

SHADOW_JAR="$DESKTOP_DIR/build/libs/desktop_bridge.jar"
if [[ ! -f "$SHADOW_JAR" ]]; then
    echo "❌ Failed to find shadow JAR at $SHADOW_JAR"
    exit 1
fi

# 2. Compile JVM Bytecode to WebAssembly using TeaVM
echo "⚡ Step 2: Compiling JAR to WebAssembly (anymex_ios_runtime.wasm)..."

TOOLS_DIR="$SCRIPT_DIR/.tools"
mkdir -p "$TOOLS_DIR"
TEAVM_JAR="$TOOLS_DIR/teavm-cli-${TEAVM_CLI_VERSION}.jar"

if [[ ! -f "$TEAVM_JAR" ]]; then
    echo "⬇️ Downloading TeaVM CLI compiler ${TEAVM_CLI_VERSION}..."
    curl -sSL "https://repo1.maven.org/maven2/org/teavm/teavm-cli/${TEAVM_CLI_VERSION}/teavm-cli-${TEAVM_CLI_VERSION}.jar" -o "$TEAVM_JAR"
fi

WASM_OUT_DIR="$DESKTOP_DIR/build/wasm"
mkdir -p "$WASM_OUT_DIR"

java -jar "$TEAVM_JAR" \
    --target wasm \
    --main-class com.anymex.desktop.DesktopExtensionLoaderKt \
    --output-dir "$WASM_OUT_DIR" \
    --output-file anymex_ios_runtime.wasm \
    --minified \
    --optimization advanced \
    "$SHADOW_JAR"

if [[ -f "$WASM_OUT_DIR/anymex_ios_runtime.wasm" ]]; then
    cp -f "$WASM_OUT_DIR/anymex_ios_runtime.wasm" "$OUTPUT_DIR/anymex_ios_runtime.wasm"
    echo "✅ Successfully built: $OUTPUT_DIR/anymex_ios_runtime.wasm"
else
    echo "❌ Error: WASM output file was not generated."
    exit 1
fi
