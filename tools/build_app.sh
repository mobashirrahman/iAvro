#!/usr/bin/env bash
# Builds "Avro Keyboard.app" and an installer .pkg with only the Command Line
# Tools (no Xcode): clang for the code, the checked-in compiled nibs, and the
# compiled asset catalog (Assets.car / AppIcon.icns) from a previous Xcode
# build, since actool needs Xcode.
#
# usage: tools/build_app.sh [path/to/previous/Avro Keyboard.app or .pkg]
#   Output: build/clang/Avro Keyboard.app and build/clang/AvroKeyboard.pkg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Avro Keyboard"
BUNDLE_ID="com.omicronlab.inputmethod.AvroKeyboard"
PKG_ID="com.omicronlab.iAvro"
PKG_VERSION="${PKG_VERSION:-2.0.6}"
ARCHS=(-arch arm64 -arch x86_64)
MIN_OS="11.0"

OUT="$ROOT/build/clang"
OBJ="$OUT/obj"
APP="$OUT/$APP_NAME.app"
ASSET_SOURCE="${1:-$ROOT/AvroKeyboard.pkg}"

rm -rf "$OUT"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ─── Compiled asset catalog from a previous build ─────────────────────────────
if [[ "$ASSET_SOURCE" == *.pkg ]]; then
    EXPANDED="$OUT/asset-source"
    pkgutil --expand-full "$ASSET_SOURCE" "$EXPANDED" >/dev/null
    ASSET_APP="$(find "$EXPANDED" -name "$APP_NAME.app" -type d | head -1)"
else
    ASSET_APP="$ASSET_SOURCE"
fi
for f in Assets.car AppIcon.icns; do
    if [[ ! -f "$ASSET_APP/Contents/Resources/$f" ]]; then
        echo "❌ $f not found in $ASSET_SOURCE (needs a previous Xcode build)" >&2
        exit 1
    fi
    cp "$ASSET_APP/Contents/Resources/$f" "$APP/Contents/Resources/"
done

# ─── Compile ──────────────────────────────────────────────────────────────────
COMMON=("${ARCHS[@]}" -mmacosx-version-min="$MIN_OS" -O2 -g -DCOCOAPODS=1
        -I"$ROOT" -I"$ROOT/Pods/RegexKitLite/RegexKitLite-4.0" -I"$ROOT/Pods/FMDB/src/fmdb")

echo "🔨 Compiling app (manual retain/release, like the Xcode target)"
for src in *.m; do
    clang "${COMMON[@]}" -fno-objc-arc -include AvroKeyboard_Prefix.pch \
        -Wno-deprecated-declarations -c "$src" -o "$OBJ/${src%.m}.o"
done

echo "🔨 Compiling pods"
clang "${COMMON[@]}" -fno-objc-arc -w -c Pods/RegexKitLite/RegexKitLite-4.0/RegexKitLite.m -o "$OBJ/RegexKitLite.o"
for src in Pods/FMDB/src/fmdb/*.m; do
    # FMDB's podspec requires ARC
    clang "${COMMON[@]}" -fobjc-arc -w -c "$src" -o "$OBJ/pod-$(basename "${src%.m}").o"
done

echo "🔗 Linking"
clang "${ARCHS[@]}" -mmacosx-version-min="$MIN_OS" "$OBJ"/*.o \
    -framework Cocoa -framework InputMethodKit -licucore -lsqlite3 -ObjC \
    -o "$APP/Contents/MacOS/$APP_NAME"

# ─── Resources ────────────────────────────────────────────────────────────────
echo "📁 Copying resources"
R="$APP/Contents/Resources"
cp autodict.plist data.json regex.json database.db3 preferences.plist "$R/"
cp Icons/AutoCorrect.png Icons/Credits.png Icons/General.png "$R/"
cp -R Credits.rtfd "$R/"
mkdir -p "$R/English.lproj"
cp English.lproj/InfoPlist.strings "$R/English.lproj/"
for nib in MainMenu preferences; do
    # Ship the compiled object graph only, not the designable source
    mkdir -p "$R/English.lproj/$nib.nib"
    cp "English.lproj/$nib.nib/keyedobjects.nib" "$R/English.lproj/$nib.nib/"
done

# ─── Info.plist (what Xcode would process) ────────────────────────────────────
PLIST="$APP/Contents/Info.plist"
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" Info.plist > "$PLIST"
plutil -replace CFBundleIconFile -string AppIcon "$PLIST"
plutil -replace CFBundleIconName -string AppIcon "$PLIST"
plutil -replace LSMinimumSystemVersion -string "$MIN_OS" "$PLIST"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$PLIST"
plutil -lint "$PLIST" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Repo files may be private (0600). Installed under /Library they are owned
# by root, and the input method runs as the user, so it couldn't read
# data.json and quit at launch.
chmod -R u=rwX,go=rX "$APP"
# Drop extended attributes (provenance/quarantine) copied from the repo
xattr -cr "$APP"

echo "🔏 Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

# ─── Package ──────────────────────────────────────────────────────────────────
echo "📦 Packaging"
STAGING="$OUT/pkgroot"
SCRIPTS="$OUT/pkgscripts"
mkdir -p "$STAGING/Library/Input Methods" "$SCRIPTS"
cp -R "$APP" "$STAGING/Library/Input Methods/"
cat > "$SCRIPTS/postinstall" <<'EOF'
#!/usr/bin/env bash
# The input method keeps running the old binary until it is restarted
killall "Avro Keyboard" 2>/dev/null || true
# Restart SystemUIServer so macOS detects the newly installed Input Method
killall SystemUIServer 2>/dev/null || true
exit 0
EOF
chmod +x "$SCRIPTS/postinstall"
pkgbuild --quiet --root "$STAGING" --scripts "$SCRIPTS" \
    --identifier "$PKG_ID" --version "$PKG_VERSION" --install-location / \
    "$OUT/AvroKeyboard.pkg"

rm -rf "$OBJ" "$STAGING" "$SCRIPTS" "${EXPANDED:-}"
echo "✅ $APP"
echo "✅ $OUT/AvroKeyboard.pkg"
