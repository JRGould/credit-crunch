#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/CreditCrunch.app"
build="$root/.build/release/CodexCreditsMenubar"

cd "$root"
swift build -c release
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$build" "$app/Contents/MacOS/CreditCrunch"
cp "$root/Sources/CodexCreditsMenubar/Resources/CreditCrunch.icns" "$app/Contents/Resources/CreditCrunch.icns"
resource_bundle="$root/.build/release/CodexCreditsMenubar_CodexCreditsMenubar.bundle"
if [[ -d "$resource_bundle" ]]; then
  cp -R "$resource_bundle" "$app/Contents/Resources/"
fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CreditCrunch</string>
  <key>CFBundleIdentifier</key><string>local.codex.credits-menubar</string>
  <key>CFBundleIconFile</key><string>CreditCrunch.icns</string>
  <key>CFBundleName</key><string>CreditCrunch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "Built $app"
