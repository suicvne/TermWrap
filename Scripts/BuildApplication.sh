#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TermWrap"
BUILD_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PREVIOUS_BUILDS_DIR="$BUILD_DIR/PreviousBuilds"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
swift build -c release --product "$APP_NAME"
swift build -c release --product TermWrapHost \
    -Xswiftc -Osize \
    -Xswiftc -gnone \
    -Xlinker -dead_strip

if [[ -e "$APP_DIR" ]]; then
    case "$APP_DIR" in
        "$BUILD_DIR"/*.app) ;;
        *)
            echo "Refusing to replace unexpected path: $APP_DIR" >&2
            exit 1
            ;;
    esac

    mkdir -p "$PREVIOUS_BUILDS_DIR"
    ARCHIVE_DIR="$PREVIOUS_BUILDS_DIR/$APP_NAME-$(date +%Y%m%d-%H%M%S).app"
    mv "$APP_DIR" "$ARCHIVE_DIR"
fi

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR/Templates"
cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp ".build/release/TermWrapHost" "$RESOURCES_DIR/TermWrapHost"
strip -x "$RESOURCES_DIR/TermWrapHost"
if [[ -d ".build/release/SwiftTerm_SwiftTerm.bundle" ]]; then
    cp -R ".build/release/SwiftTerm_SwiftTerm.bundle" "$RESOURCES_DIR/SwiftTerm_SwiftTerm.bundle"
fi
cp "Sources/TermWrap/Resources/Templates/Info.plist.template" "$RESOURCES_DIR/Templates/Info.plist.template"
cp "Sources/TermWrap/Resources/Templates/Entitlements.plist.template" "$RESOURCES_DIR/Templates/Entitlements.plist.template"
cp "Sources/TermWrapHost/main.swift" "$RESOURCES_DIR/Templates/TermWrapHost.swift.template"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>TermWrap</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>xyz.ignoresolutions.termwrap</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TermWrap</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
