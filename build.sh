#!/bin/bash
set -e

APP="ClaudeUsage.app"
DMG="ClaudeUsage.dmg"

# --- Compile ---
swift build -c release 2>&1

# --- App icon ---
swift Scripts/make-icon.swift
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
rm -rf AppIcon.iconset

# --- .app bundle ---
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/ClaudeUsage "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
echo "✅ Built $APP"

# --- DMG installer ---
DMG_TEMP="dmg_stage"
rm -rf "$DMG_TEMP" "$DMG"
mkdir -p "$DMG_TEMP"
cp -r "$APP" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"
hdiutil create -volname "ClaudeUsage" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG"
rm -rf "$DMG_TEMP"
echo "✅ Built $DMG"
