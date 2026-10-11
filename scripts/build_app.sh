#!/usr/bin/env bash
set -euo pipefail

echo "🔨 Building MacTaskCleanerApp..."
swift build -c release --target MacTaskCleanerApp

BIN_PATH="$(swift build -c release --show-bin-path)"
APP_DIR="${BIN_PATH}/MacTaskCleaner.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp -f "${BIN_PATH}/MacTaskCleanerApp" "${MACOS_DIR}/MacTaskCleaner"
chmod +x "${MACOS_DIR}/MacTaskCleaner"

# Generate Info.plist for Menu Bar Application (LSUIElement = true)
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.mactaskcleaner.app</string>
    <key>CFBundleName</key>
    <string>MacTaskCleaner</string>
    <key>CFBundleDisplayName</key>
    <string>맥 작업정리</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleExecutable</key>
    <string>MacTaskCleaner</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ MacTaskCleaner.app successfully built at: ${APP_DIR}"
