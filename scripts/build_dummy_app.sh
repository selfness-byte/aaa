#!/usr/bin/env bash
set -euo pipefail

# Build DummyTestTarget executable via SPM
swift build --target DummyTestTarget

# Locate build directory
BIN_PATH="$(swift build --show-bin-path)"
APP_DIR="${BIN_PATH}/DummyTestTarget.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

mkdir -p "${MACOS_DIR}"

# Copy executable
cp -f "${BIN_PATH}/DummyTestTarget" "${MACOS_DIR}/DummyTestTarget"
chmod +x "${MACOS_DIR}/DummyTestTarget"

# Generate Info.plist for AppKit execution
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.mactaskcleaner.dummytesttarget</string>
    <key>CFBundleName</key>
    <string>DummyTestTarget</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DummyTestTarget</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

echo "✅ DummyTestTarget.app successfully prepared at: ${APP_DIR}"
