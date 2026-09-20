#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/scripts/toolchain.sh"
icon_dir="$project_dir/.build/AppIcon.iconset"
mkdir -p "$icon_dir"
swift "$project_dir/make-icon.swift" "$project_dir/.build/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_dir/.build/AppIcon.png" --out "$icon_dir/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$project_dir/.build/AppIcon.png" --out "$icon_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_dir" -o "$project_dir/AppIcon.icns"
