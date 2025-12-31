#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="SeekQool"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle not found at $APP_BUNDLE"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

# Create ~/Applications if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Remove existing installation
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "Removing existing installation..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Copy app bundle
echo "Installing $APP_NAME to $INSTALL_DIR..."
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

# Clear quarantine attribute
xattr -cr "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

echo ""
echo "Installation complete!"
echo "Location: $INSTALL_DIR/$APP_NAME.app"
echo ""
echo "You can now launch SeekQool from:"
echo "  - Spotlight (Cmd+Space, type 'SeekQool')"
echo "  - Finder > ~/Applications"
echo "  - Terminal: open '$INSTALL_DIR/$APP_NAME.app'"
