#!/bin/bash
set -e

# Build the app bundle for PR Review System

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$APP_DIR/.build/release"
BUNDLE_DIR="$APP_DIR/.build/PRReview.app"

echo "Building PRReviewSystem..."
cd "$APP_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/PRReviewSystem" "$BUNDLE_DIR/Contents/MacOS/"

# Copy Info.plist
cp "$APP_DIR/Resources/Info.plist" "$BUNDLE_DIR/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

echo "App bundle created at: $BUNDLE_DIR"
echo ""
echo "To install:"
echo "  cp -r $BUNDLE_DIR /Applications/"
echo ""
echo "To run:"
echo "  open /Applications/PRReview.app"
