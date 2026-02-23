#!/bin/bash
set -e

APP="ClaudeUsage.app"
swift build -c release 2>&1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeUsage "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

echo "✅ Built $APP"
echo "   Install: cp -r $APP /Applications/"
