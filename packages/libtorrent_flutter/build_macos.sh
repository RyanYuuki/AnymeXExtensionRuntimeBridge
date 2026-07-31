#!/bin/bash
# Build liblibtorrent_flutter.dylib for macOS and bundle OpenSSL dylibs.
# Run on macOS with Homebrew libtorrent and openssl@3 installed:
#   brew install libtorrent-rasterbar openssl@3
#   chmod +x build_macos.sh && ./build_macos.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
BUILD_DIR="$SRC_DIR/build_macos"
MACOS_DIR="$SCRIPT_DIR/macos"
PREBUILT_DIR="$SCRIPT_DIR/prebuilt/macos/universal"

# Detect Homebrew prefix (ARM vs Intel)
if [ -d "/opt/homebrew" ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

OPENSSL_PREFIX="$BREW_PREFIX/opt/openssl@3"

echo "=== Homebrew prefix: $BREW_PREFIX"
echo "=== OpenSSL prefix:  $OPENSSL_PREFIX"

# ── Build ──────────────────────────────────────────────────────────────────────
echo "=== Configuring..."
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release

echo "=== Building..."
cmake --build "$BUILD_DIR" --config Release --parallel

DYLIB="$BUILD_DIR/liblibtorrent_flutter.dylib"
if [ ! -f "$DYLIB" ]; then
    echo "ERROR: Build failed — dylib not found at $DYLIB"
    exit 1
fi

# ── Fix OpenSSL load paths ─────────────────────────────────────────────────────
echo "=== Fixing OpenSSL load paths with install_name_tool..."

# The POST_BUILD in CMake already does this, but run it again to be safe
for ssl_path in "$BREW_PREFIX/opt/openssl@3/lib" "$BREW_PREFIX/opt/openssl/lib" "/opt/homebrew/opt/openssl@3/lib" "/usr/local/opt/openssl@3/lib"; do
    install_name_tool -change "$ssl_path/libssl.3.dylib" "@loader_path/libssl.3.dylib" "$DYLIB" 2>/dev/null || true
    install_name_tool -change "$ssl_path/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" "$DYLIB" 2>/dev/null || true
done

# ── Copy & fix OpenSSL dylibs ──────────────────────────────────────────────────
echo "=== Bundling OpenSSL dylibs..."

for dest in "$MACOS_DIR" "$PREBUILT_DIR"; do
    mkdir -p "$dest"
    cp "$DYLIB" "$dest/"

    # Copy OpenSSL dylibs
    cp "$OPENSSL_PREFIX/lib/libssl.3.dylib" "$dest/"
    cp "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "$dest/"

    # Fix libssl's reference to libcrypto
    install_name_tool -change "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" "$dest/libssl.3.dylib"

    # Fix install names to use @loader_path
    install_name_tool -id "@loader_path/libssl.3.dylib" "$dest/libssl.3.dylib"
    install_name_tool -id "@loader_path/libcrypto.3.dylib" "$dest/libcrypto.3.dylib"

    echo "  -> $dest/ (dylib + libssl + libcrypto)"
done

# ── Verify ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Verifying linkage..."
echo "--- liblibtorrent_flutter.dylib ---"
otool -L "$MACOS_DIR/liblibtorrent_flutter.dylib" | grep -E "ssl|crypto|homebrew" || echo "  (no Homebrew references — OK)"
echo "--- libssl.3.dylib ---"
otool -L "$MACOS_DIR/libssl.3.dylib" | grep -E "crypto|homebrew" || echo "  (no Homebrew references — OK)"

echo ""
echo "=== Done! Files placed in:"
echo "  $MACOS_DIR/"
echo "  $PREBUILT_DIR/"
echo ""
echo "Verify with: otool -L $MACOS_DIR/liblibtorrent_flutter.dylib"
