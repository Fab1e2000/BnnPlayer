#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BananaPlayer"
BUNDLE_ID="com.bananaplayer.app"
VERSION="${1:-1.0.0}"
SHORT_VERSION="${2:-1.0}"

BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
BIN_PATH="$BUILD_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macos.zip"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_SOURCE_PNG="$DIST_DIR/AppIcon-1024.png"
ICON_FILE_NAME="AppIcon"
ROOT_LOGO_PNG="$ROOT_DIR/logo.png"
CUSTOM_ICON_PNG=""

generate_music_icon_png() {
  local output_png="$1"
  swift - "$output_png" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)

image.lockFocus()

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()

let iconRect = NSRect(x: 88, y: 88, width: 848, height: 848)
let clippingPath = NSBezierPath(roundedRect: iconRect, xRadius: 190, yRadius: 190)
clippingPath.addClip()

let gradient = NSGradient(
  colors: [
    NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.84, alpha: 1.0),
    NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.24, alpha: 1.0),
    NSColor(calibratedRed: 0.98, green: 0.73, blue: 0.09, alpha: 1.0)
  ]
)
gradient?.draw(in: iconRect, angle: -55)

let glow = NSBezierPath(ovalIn: NSRect(x: 190, y: 540, width: 530, height: 240))
NSColor(calibratedWhite: 1.0, alpha: 0.22).setFill()
glow.fill()

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0.2, alpha: 0.18)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()

let note = NSBezierPath()
note.move(to: NSPoint(x: 592, y: 714))
note.curve(to: NSPoint(x: 592, y: 378),
           controlPoint1: NSPoint(x: 592, y: 650),
           controlPoint2: NSPoint(x: 592, y: 460))
note.curve(to: NSPoint(x: 740, y: 416),
           controlPoint1: NSPoint(x: 646, y: 390),
           controlPoint2: NSPoint(x: 704, y: 404))
note.curve(to: NSPoint(x: 700, y: 318),
           controlPoint1: NSPoint(x: 744, y: 370),
           controlPoint2: NSPoint(x: 726, y: 336))
note.curve(to: NSPoint(x: 540, y: 280),
           controlPoint1: NSPoint(x: 654, y: 290),
           controlPoint2: NSPoint(x: 592, y: 276))
note.curve(to: NSPoint(x: 448, y: 360),
           controlPoint1: NSPoint(x: 484, y: 284),
           controlPoint2: NSPoint(x: 448, y: 316))
note.curve(to: NSPoint(x: 532, y: 446),
           controlPoint1: NSPoint(x: 448, y: 408),
           controlPoint2: NSPoint(x: 484, y: 446))
note.curve(to: NSPoint(x: 640, y: 438),
           controlPoint1: NSPoint(x: 568, y: 446),
           controlPoint2: NSPoint(x: 604, y: 444))
note.curve(to: NSPoint(x: 640, y: 748),
           controlPoint1: NSPoint(x: 640, y: 528),
           controlPoint2: NSPoint(x: 640, y: 648))
note.curve(to: NSPoint(x: 468, y: 710),
           controlPoint1: NSPoint(x: 586, y: 736),
           controlPoint2: NSPoint(x: 520, y: 720))
note.curve(to: NSPoint(x: 468, y: 780),
           controlPoint1: NSPoint(x: 468, y: 730),
           controlPoint2: NSPoint(x: 468, y: 756))
note.curve(to: NSPoint(x: 682, y: 822),
           controlPoint1: NSPoint(x: 528, y: 804),
           controlPoint2: NSPoint(x: 612, y: 818))
note.curve(to: NSPoint(x: 770, y: 742),
           controlPoint1: NSPoint(x: 736, y: 822),
           controlPoint2: NSPoint(x: 770, y: 790))
note.curve(to: NSPoint(x: 770, y: 358),
           controlPoint1: NSPoint(x: 770, y: 674),
           controlPoint2: NSPoint(x: 770, y: 470))
note.curve(to: NSPoint(x: 592, y: 306),
           controlPoint1: NSPoint(x: 714, y: 332),
           controlPoint2: NSPoint(x: 646, y: 316))
note.curve(to: NSPoint(x: 530, y: 342),
           controlPoint1: NSPoint(x: 568, y: 306),
           controlPoint2: NSPoint(x: 544, y: 320))
note.curve(to: NSPoint(x: 530, y: 714),
           controlPoint1: NSPoint(x: 530, y: 426),
           controlPoint2: NSPoint(x: 530, y: 610))
note.close()

NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.95).setFill()
note.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let border = NSBezierPath(roundedRect: iconRect, xRadius: 190, yRadius: 190)
NSColor(calibratedWhite: 0.95, alpha: 0.35).setStroke()
border.lineWidth = 3
border.stroke()

image.unlockFocus()

guard
  let tiff = image.tiffRepresentation,
  let rep = NSBitmapImageRep(data: tiff),
  let png = rep.representation(using: .png, properties: [:])
else {
  fputs("Failed to render app icon\n", stderr)
  exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT
}

printf "==> Building release binary...\n"
cd "$ROOT_DIR"
swift build -c release

if [[ ! -x "$BIN_PATH" ]]; then
  printf "Error: release binary not found at %s\n" "$BIN_PATH" >&2
  exit 1
fi

printf "==> Creating app bundle...\n"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

mkdir -p "$DIST_DIR"
rm -rf "$ICONSET_DIR"

if [[ -f "$ROOT_LOGO_PNG" ]]; then
  CUSTOM_ICON_PNG="$ROOT_LOGO_PNG"
else
  CUSTOM_ICON_PNG="$(find "$DIST_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.PNG' \) ! -name 'AppIcon-1024.png' | head -n 1)"
fi

if [[ -n "$CUSTOM_ICON_PNG" ]]; then
  printf "==> Using custom PNG app icon: %s\n" "$CUSTOM_ICON_PNG"
  cp "$CUSTOM_ICON_PNG" "$ICON_SOURCE_PNG"
else
  printf "==> Generating yellow music app icon...\n"
  generate_music_icon_png "$ICON_SOURCE_PNG"
fi

mkdir -p "$ICONSET_DIR"

for size in 16 32 64 128 256 512; do
  sips -s format png -z "$size" "$size" "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -s format png -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$ICON_FILE_NAME.icns"
rm -rf "$ICONSET_DIR" "$ICON_SOURCE_PNG"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_FILE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

printf "==> Creating zip artifact...\n"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
(
  cd "$DIST_DIR"
  ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP_PATH")"
)

printf "\nDone.\n"
printf "App bundle: %s\n" "$APP_DIR"
printf "Zip artifact: %s\n" "$ZIP_PATH"
