#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/GPU Monitor.app"
[ -d "$app_dir" ] || { echo "Run bash build.sh first." >&2; exit 1; }
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/gpu-monitor-package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto --norsrc "$app_dir" "$staging_dir/GPU Monitor.app"
app_dir="$staging_dir/GPU Monitor.app"
xattr -cr "$app_dir"
codesign --verify --deep --strict "$app_dir"
architecture="$(uname -m)"
archive="GPU-Monitor-macOS-$architecture.zip"
ditto -c -k --norsrc --keepParent "$app_dir" "$project_dir/dist/$archive"
(cd "$project_dir/dist" && shasum -a 256 "$archive" > SHA256SUMS.txt)
printf 'Packaged: %s\n' "$project_dir/dist/$archive"
