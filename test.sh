#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
source "$project_dir/scripts/toolchain.sh"
mkdir -p "$project_dir/.build/checks"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$project_dir/Tests" -p 'test_*.py' -v
swiftc -module-cache-path "$project_dir/.build/module-cache" \
    "$project_dir/Sources/GPUMonitor/Models.swift" \
    "$project_dir/Sources/GPUMonitor/JobTracker.swift" \
    "$project_dir/Sources/GPUMonitor/SSHProvider.swift" \
    "$project_dir/Tests/Swift/JobTrackerTests.swift" \
    -o "$project_dir/.build/checks/gpu-monitor-checks"
"$project_dir/.build/checks/gpu-monitor-checks"
swiftc -parse-as-library -module-cache-path "$project_dir/.build/module-cache" \
    "$project_dir/Sources/GPUMonitor/Models.swift" \
    "$project_dir/Sources/GPUMonitor/JobTracker.swift" \
    "$project_dir/Sources/GPUMonitor/SSHProvider.swift" \
    "$project_dir/Sources/GPUMonitor/Presentation.swift" \
    "$project_dir/Sources/GPUMonitor/Monitor.swift" \
    "$project_dir/Sources/GPUMonitor/Appearance.swift" \
    "$project_dir/Sources/GPUMonitor/GPUPieIcon.swift" \
    "$project_dir/Tests/Swift/MonitorTests.swift" \
    -o "$project_dir/.build/checks/gpu-monitor-integration-checks"
"$project_dir/.build/checks/gpu-monitor-integration-checks"
swiftc -parse-as-library -module-cache-path "$project_dir/.build/module-cache" \
    "$project_dir/Sources/GPUMonitor/Models.swift" \
    "$project_dir/Sources/GPUMonitor/Appearance.swift" \
    "$project_dir/Sources/GPUMonitor/GPUPieIcon.swift" \
    "$project_dir/Tests/Swift/MenuIconTests.swift" \
    -o "$project_dir/.build/checks/gpu-monitor-icon-checks"
"$project_dir/.build/checks/gpu-monitor-icon-checks"
swiftc -parse-as-library -module-cache-path "$project_dir/.build/module-cache" \
    "$project_dir/Sources/GPUMonitor/Models.swift" \
    "$project_dir/Sources/GPUMonitor/Presentation.swift" \
    "$project_dir/Tests/Swift/PresentationTests.swift" \
    -o "$project_dir/.build/checks/gpu-monitor-presentation-checks"
"$project_dir/.build/checks/gpu-monitor-presentation-checks"
swiftc -parse-as-library -module-cache-path "$project_dir/.build/module-cache" \
    "$project_dir/Sources/GPUMonitor/Models.swift" \
    "$project_dir/Sources/GPUMonitor/Appearance.swift" \
    "$project_dir/Sources/GPUMonitor/MenuBarPanel.swift" \
    "$project_dir/Tests/Swift/MenuBarPanelTests.swift" \
    -o "$project_dir/.build/checks/gpu-monitor-panel-checks"
"$project_dir/.build/checks/gpu-monitor-panel-checks"
