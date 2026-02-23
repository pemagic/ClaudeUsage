#!/bin/bash
set -e

APP="ClaudeUsage.app"
swift build -c release 2>&1

# Generate app icon
swift Scripts/make-icon.swift
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
rm -rf AppIcon.iconset

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/ClaudeUsage "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "✅ Built $APP"
echo "   Install: cp -r $APP /Applications/"
