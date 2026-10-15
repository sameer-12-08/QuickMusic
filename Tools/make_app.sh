#!/bin/bash
# Builds build/QuickFLAC.app from the Swift package.
#
#   bash Tools/make_app.sh
#   open build/QuickFLAC.app
#
# An .app is just a folder with a known layout:
#   QuickFLAC.app/Contents/Info.plist        describes the app to macOS
#   QuickFLAC.app/Contents/MacOS/QuickFLAC   the program itself
#   QuickFLAC.app/Contents/Resources/        data files (our themes.json)
set -euo pipefail

cd "$(dirname "$0")/.."          # project root, wherever you run the script from
APP="build/QuickFLAC.app"

echo "Building (release)..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "Creating $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/QuickFLAC" "$APP/Contents/MacOS/QuickFLAC"
cp Tools/Info.plist "$APP/Contents/Info.plist"
cp Sources/QuickFLAC/Resources/themes.json "$APP/Contents/Resources/themes.json"

# "Ad-hoc" signing (identity "-") needs no Apple developer account. It is enough
# for an app you built yourself and run on your own Mac.
codesign --force --sign - "$APP"

echo "Done: $APP"
echo "Run it with:  open $APP"
