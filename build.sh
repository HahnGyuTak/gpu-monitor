#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$project_dir/dist"
build_dir="$project_dir/.build/release-build"
source "$project_dir/scripts/toolchain.sh"
mkdir -p "$output_dir"
swift build --disable-sandbox --package-path "$project_dir" --scratch-path "$build_dir" --cache-path "$project_dir/.build/swift-cache" -c release
# Sign outside synced folders, whose Finder metadata can be rewritten during signing.
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/gpu-monitor-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
app_dir="$staging_dir/GPU Monitor.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/release/GPUMonitor" "$app_dir/Contents/MacOS/GPUMonitor"
# App bundles use their own resource path; CLI builds use Bundle.module.
if [ -d "$app_dir/Contents/MacOS/GPUMonitor_GPUMonitor.bundle" ]; then
    rm -r "$app_dir/Contents/MacOS/GPUMonitor_GPUMonitor.bundle"
fi
cp "$project_dir/Sources/GPUMonitor/Resources/collector.py" "$app_dir/Contents/Resources/collector.py"
cp "$project_dir/Sources/GPUMonitor/Resources/host_pid_map.py" "$app_dir/Contents/Resources/host_pid_map.py"
cp "$project_dir/Sources/GPUMonitor/Resources/tmux_sessions.py" "$app_dir/Contents/Resources/tmux_sessions.py"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GPUMonitor</string>
<key>CFBundleIdentifier</key><string>dev.gthahn.gpu-monitor</string>
<key>CFBundleName</key><string>GPU Monitor</string>
<key>CFBundleDisplayName</key><string>GPU Monitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9.6</string>
<key>CFBundleVersion</key><string>21</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
if [ -f "$project_dir/AppIcon.icns" ]; then cp "$project_dir/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"; fi
# Clear Finder metadata on this newly generated bundle before signing.
xattr -cr "$app_dir"
signing_identity="${CODESIGN_IDENTITY:-}"
if [ -z "$signing_identity" ]; then
    signing_identity="$(security find-identity -v -p codesigning | awk '/Apple Development:/ && !identity {identity=$2} END {print identity}')"
fi
codesign --force --deep --timestamp=none --sign "${signing_identity:--}" "$app_dir"
codesign --verify --deep --strict "$app_dir"
ditto --norsrc "$app_dir" "$output_dir/GPU Monitor.app"
printf 'Built: %s\n' "$output_dir/GPU Monitor.app"
