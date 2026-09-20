import AppKit

struct GPUPieSlice: Equatable {
    var index: Int
    var active: Bool
}

struct GPUPieState {
    var server: String?
    var slices: [GPUPieSlice]
    var status: String?

    var toolTip: String {
        let heading = server.map { "GPU Monitor · \($0)" } ?? "GPU Monitor"
        let summary = slices.map { "GPU \($0.index): \($0.active ? "활성" : "대기")" }.joined(separator: " · ")
        let order = slices.count == 4
            ? zip(["우상단", "우하단", "좌하단", "좌상단"], slices).map { "\($0.0) GPU \($0.1.index)" }.joined(separator: " → ")
            : "12시부터 시계 방향 · GPU 번호순"
        return [heading, status, summary.isEmpty ? nil : summary, slices.isEmpty ? nil : order].compactMap { $0 }.joined(separator: "\n")
    }

    static func make(server: String?, gpus: [GPU], panes: [Pane] = [], status: String? = nil) -> GPUPieState {
        let mapped = Set(panes.filter(\.active).flatMap(\.gpuIDs))
        return GPUPieState(server: server, slices: gpus.sorted { $0.index < $1.index }.map {
            GPUPieSlice(index: $0.index, active: status == nil &&
                ($0.hasComputeProcess == true || ($0.utilization ?? 0) > 0 || mapped.contains($0.id)))
        }, status: status)
    }
}

enum GPUPieIcon {
    static let size = NSSize(width: 20, height: 20)

    static func image(for state: GPUPieState) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(slices: state.slices, in: rect)
            return true
        }
        // Active wedges retain their color; inactive wedges follow light/dark appearance.
        image.isTemplate = false
        image.accessibilityDescription = state.toolTip
        return image
    }

    static func draw(slices: [GPUPieSlice], in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.425
        let inactive = NSColor.labelColor.withAlphaComponent(0.23)
        let active = NSColor(calibratedRed: 0.08, green: 0.72, blue: 0.49, alpha: 1)
        guard !slices.isEmpty else {
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 1.3
            ring.stroke()
            return
        }
        if slices.count == 1 {
            (slices[0].active ? active : inactive).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            return
        }
        let sweep = 360.0 / Double(slices.count)
        for (offset, slice) in slices.enumerated() {
            let start = 90 - Double(offset) * sweep
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
            wedge.close()
            (slice.active ? active : inactive).setFill()
            wedge.fill()
        }
        // Transparent spokes expose the menu bar itself, so all-active still has N visible slices.
        context.setBlendMode(.clear)
        context.setLineWidth(min(rect.width, rect.height) * 0.06)
        for offset in slices.indices {
            let angle = (90 - Double(offset) * sweep) * .pi / 180
            context.move(to: center)
            context.addLine(to: NSPoint(x: center.x + (radius + 1) * cos(angle), y: center.y + (radius + 1) * sin(angle)))
            context.strokePath()
        }
    }
}
