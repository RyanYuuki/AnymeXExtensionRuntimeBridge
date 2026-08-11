#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

usage() {
    echo "Usage: $0 [android|desktop|wasm|all|clean-android|clean-desktop|clean-all]"
    echo
    echo "  android        Build the Android runtime host APK and push via ADB"
    echo "  desktop        Build the Desktop bridge JAR and copy to ~/Documents/AnymeX/Tools"
    echo "  wasm           Build the iOS WASM runtime host (anymex_ios_runtime.wasm)"
    echo "  all            Build Android, Desktop, and iOS WASM"
    echo "  clean-android  Clean + build Android"
    echo "  clean-desktop  Clean + build Desktop"
    echo "  clean-all      Clean + build all targets"
    echo
    echo "If no argument is given you will be prompted to choose."
}

clean_android() {
    echo
    echo "======================================="
    echo " Cleaning Android Runtime Host"
    echo "======================================="
    (cd "$SCRIPT_DIR/RuntimeBridges/Android" && ./gradlew clean)
    echo "✅ Android clean done"
}

clean_desktop() {
    echo
    echo "======================================="
    echo " Cleaning Desktop Bridge"
    echo "======================================="
    (cd "$SCRIPT_DIR/RuntimeBridges/Desktop" && ./gradlew clean)
    echo "✅ Desktop clean done"
}

build_android() {
    echo
    echo "======================================="
    echo " Building Android Runtime Host"
    echo "======================================="
    bash "$SCRIPT_DIR/RuntimeBridges/Android/build.sh"

    mkdir -p "$OUTPUT_DIR"
    if [[ -f "$SCRIPT_DIR/RuntimeBridges/Android/anymex_runtime_host.apk" ]]; then
        cp -f "$SCRIPT_DIR/RuntimeBridges/Android/anymex_runtime_host.apk" "$OUTPUT_DIR/anymex_runtime_host.apk"
        echo "📦 Copied APK to $OUTPUT_DIR/anymex_runtime_host.apk"
    fi
}

build_desktop() {
    echo
    echo "======================================="
    echo " Building Desktop Bridge"
    echo "======================================="
    bash "$SCRIPT_DIR/build_desktop.sh"

    mkdir -p "$OUTPUT_DIR"
    if [[ -f "$SCRIPT_DIR/RuntimeBridges/Desktop/build/libs/desktop_bridge.jar" ]]; then
        cp -f "$SCRIPT_DIR/RuntimeBridges/Desktop/build/libs/desktop_bridge.jar" "$OUTPUT_DIR/anymex_desktop_runtime.jar"
        echo "📦 Copied JAR to $OUTPUT_DIR/anymex_desktop_runtime.jar"
    fi
}

build_wasm() {
    echo
    echo "======================================="
    echo " Building iOS WASM Runtime"
    echo "======================================="
    bash "$SCRIPT_DIR/build_wasm.sh"
}

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "======================================="
    echo "  AnymeX Extension Runtime Builder"
    echo "======================================="
    echo
    echo "  1) Android        — build APK + ADB push"
    echo "  2) Desktop        — build JAR + copy"
    echo "  3) iOS WASM       — build anymex_ios_runtime.wasm"
    echo "  4) All Targets    — build Android, Desktop & iOS WASM"
    echo "  5) Clean Android  — clean + build APK"
    echo "  6) Clean Desktop  — clean + build JAR"
    echo "  7) Clean All      — clean + build all"
    echo
    read -rp "Choose [1-7]: " CHOICE
    case "$CHOICE" in
        1) TARGET="android"       ;;
        2) TARGET="desktop"       ;;
        3) TARGET="wasm"          ;;
        4) TARGET="all"           ;;
        5) TARGET="clean-android" ;;
        6) TARGET="clean-desktop" ;;
        7) TARGET="clean-all"     ;;
        *) echo "❌ Invalid choice: '$CHOICE'"; usage; exit 1 ;;
    esac
fi

case "$TARGET" in
    android)
        build_android
        ;;
    desktop)
        build_desktop
        ;;
    wasm)
        build_wasm
        ;;
    all|both)
        build_android
        build_desktop
        build_wasm
        ;;
    clean-android)
        clean_android
        build_android
        ;;
    clean-desktop)
        clean_desktop
        build_desktop
        ;;
    clean-all|clean-both)
        clean_android
        clean_desktop
        build_android
        build_desktop
        build_wasm
        ;;
    --help|-h|help)
        usage
        exit 0
        ;;
    *)
        echo "❌ Unknown target: '$TARGET'"
        usage
        exit 1
        ;;
esac

echo
echo "✅ All done! Artifacts copied to $OUTPUT_DIR/"
