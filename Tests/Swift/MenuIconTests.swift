import AppKit
import Foundation

@main struct MenuIconChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    static func legacyPreferences() throws {
        let json = #"{"servers":[{"id":"server","alias":"training-server","enabled":true}],"selected":"server/%2","menuServerID":"server","watched":["server/%2"],"notifications":true,"interval":30,"compact":true}"#
        for extra in ["", #", "menuIconStyle":"future-style","menuIconColor":"future-color""#] {
            let data = Data((String(json.dropLast()) + extra + "}").utf8)
            let prefs = try JSONDecoder().decode(Preferences.self, from: data)
            require(prefs.servers.first?.alias == "training-server", "Keep existing servers during migration")
            require(prefs.selected == "server/%2" && prefs.menuServerID == "server" && prefs.watched == ["server/%2"], "Keep menu selection and watches")
            require(prefs.notifications && prefs.compact && prefs.interval == 30, "Keep existing settings")
            require(prefs.menuIconStyle == .circles && prefs.menuIconColor == .blue, "Missing or future icon options use safe defaults")
        }
    }

    static func preferenceRoundTrips() throws {
        for style in MenuIconStyle.allCases {
            for color in MenuIconColor.allCases {
                let prefs = Preferences(menuIconStyle: style, menuIconColor: color)
                let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
                require(restored.menuIconStyle == style && restored.menuIconColor == color, "Persist every style and color")
            }
        }
    }

    static func singleCircleMapping() {
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            for count in 1...8 {
                for activeIndex in 0..<count {
                    checkCirclePositions(count: count, activeIndex: activeIndex)
                }
            }
        }
    }

    static func checkCirclePositions(count: Int, activeIndex: Int) {
        let slices: [GPUPieSlice] = (0..<count).map { GPUPieSlice(index: $0 * 2, active: $0 == activeIndex) }
        let state = GPUPieState(server: nil, slices: slices, status: nil)
        let icon = GPUPieIcon.image(for: state, color: .orange)
        require(icon.size == NSSize(width: 20, height: 20), "Keep 1–8 GPUs in one menu bar circle")
        let rendered = bitmap(icon)
        let sweep: Double = 360.0 / Double(count)
        for index in 0..<count {
            let degrees: Double = 90.0 - (Double(index) + 0.5) * sweep
            let angle: Double = degrees * Double.pi / 180.0
            let x = Int(10.0 + 6.0 * cos(angle))
            let y = Int(10.0 - 6.0 * sin(angle))
            let filled = rendered.colorAt(x: x, y: y)!.alphaComponent > 0.8
            require(filled == (index == activeIndex), "Highlight only GPU \(activeIndex) at its clockwise position among \(count) GPUs")
        }
        require(state.toolTip.contains("GPU \((count - 1) * 2):"), "Retain actual GPU indices in the description")
    }

    static func activityAndLabels() {
        let gpus = (0..<8).reversed().map { index in
            GPU(index: index, id: "g\(index)", name: "Test GPU", utilization: index == 2 ? 1 : 0, hasComputeProcess: index == 6)
        }
        let state = GPUPieState.make(server: "example", gpus: gpus)
        require(state.slices.filter(\.active).map(\.index) == [2, 6], "Only active GPUs are highlighted, in GPU order")
        require(state.toolTip.contains("12시부터 시계 방향 · GPU 번호순") && !state.toolTip.contains("원 2"), "Describe one circle in clockwise GPU order")
        require(state.toolTip(for: .bars).contains("왼쪽부터 GPU 번호순"), "Describe barcode direction")
        require(!state.toolTip(for: .bars).contains("시계 방향"), "Do not describe bars as circular")
        let paused = GPUPieState.make(server: "example", gpus: gpus, status: "일시 정지")
        require(paused.slices.allSatisfy { !$0.active }, "Stale or paused activity must not remain colored")
    }

    static func bitmap(_ image: NSImage) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func renderedLayouts() {
        for dark in [false, true] {
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                for style in MenuIconStyle.allCases {
                    for count in 0...8 {
                        let state = GPUPieState(server: nil, slices: (0..<count).map { GPUPieSlice(index: $0, active: $0 == count - 1) }, status: nil)
                        let blue = bitmap(GPUPieIcon.image(for: state, style: style, color: .blue))
                        let orange = bitmap(GPUPieIcon.image(for: state, style: style, color: .orange))
                        var differences = 0
                        var occupiedColumns = [Bool]()
                        for x in 0..<blue.pixelsWide {
                            var occupied = false
                            for y in 0..<blue.pixelsHigh {
                                if blue.colorAt(x: x, y: y) != orange.colorAt(x: x, y: y) { differences += 1 }
                                if blue.colorAt(x: x, y: y)!.alphaComponent > 0.1 { occupied = true }
                            }
                            occupiedColumns.append(occupied)
                        }
                        require(count == 0 ? differences == 0 : differences > 0, "Apply color only when a GPU is active")
                        let runs = occupiedColumns.enumerated().filter { $0.element && ($0.offset == 0 || !occupiedColumns[$0.offset - 1]) }.count
                        if style == .bars && count > 0 { require(runs == count, "Render one separate bar per GPU") }
                    }
                }
            }
        }
    }

    static func main() throws {
        try legacyPreferences(); print("PASS legacy and unknown icon preferences preserve settings")
        try preferenceRoundTrips(); print("PASS style and color persistence")
        singleCircleMapping(); print("PASS one-circle rendering and clockwise GPU mapping for 1–8 GPUs")
        activityAndLabels(); print("PASS activity, stale states and accessible ordering")
        renderedLayouts(); print("PASS light/dark icon rendering and barcode count")
        print("5 Menu icon checks passed")
    }
}
