import AppKit

struct GPUPieSlice: Equatable {
    var index: Int
    var active: Bool
}

struct GPUPieState {
    var server: String?
    var slices: [GPUPieSlice]
    var status: String?

    var toolTip: String { toolTip(for: .circles) }

    func toolTip(for style: MenuIconStyle) -> String {
        let heading = server.map { "GPU Monitor · \($0)" } ?? "GPU Monitor"
        let summary = slices.map { "GPU \($0.index): \($0.active ? "활성" : "대기")" }.joined(separator: " · ")
        let order: String
        if style == .bars {
            order = "왼쪽부터 GPU 번호순"
        } else if slices.count > 4 {
            let groups = GPUPieIcon.groups(slices).enumerated().map { index, group in
                "원 \(index + 1): " + group.map { "GPU \($0.index)" }.joined(separator: " → ")
            }.joined(separator: "\n")
            order = "왼쪽 원부터 · 각 원은 12시부터 시계 방향\n" + groups
        } else if slices.count == 4 {
            order = zip(["우상단", "우하단", "좌하단", "좌상단"], slices).map { "\($0.0) GPU \($0.1.index)" }.joined(separator: " → ")
        } else {
            order = "12시부터 시계 방향 · GPU 번호순"
        }
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
    private static let diameter: CGFloat = 20
    private static let circleGap: CGFloat = 2
    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2

    // Use the fewest circles possible, then distribute GPUs evenly (6 = 3+3, 8 = 4+4).
    static func groups(_ slices: [GPUPieSlice]) -> [[GPUPieSlice]] {
        guard !slices.isEmpty else { return [] }
        let count = (slices.count + 3) / 4
        let base = slices.count / count
        let extra = slices.count % count
        var offset = 0
        return (0..<count).map { index in
            let length = base + (index < extra ? 1 : 0)
            defer { offset += length }
            return Array(slices[offset..<(offset + length)])
        }
    }

    static func size(for state: GPUPieState, style: MenuIconStyle = .circles) -> NSSize {
        let width: CGFloat
        switch style {
        case .circles:
            let count = CGFloat(max(1, groups(state.slices).count))
            width = count * diameter + (count - 1) * circleGap
        case .bars:
            width = max(diameter, CGFloat(state.slices.count) * (barWidth + barGap) - barGap + 4)
        }
        return NSSize(width: width, height: diameter)
    }

    static func image(for state: GPUPieState, style: MenuIconStyle = .circles, color: MenuIconColor = .blue) -> NSImage {
        let image = NSImage(size: size(for: state, style: style), flipped: false) { rect in
            let active = MonitorAppearance.iconColor(color)
            switch style {
            case .circles:
                let grouped = groups(state.slices)
                if grouped.isEmpty { drawCircle(slices: [], in: rect, active: active) }
                for (index, group) in grouped.enumerated() {
                    let bounds = NSRect(x: rect.minX + CGFloat(index) * (diameter + circleGap), y: rect.minY, width: diameter, height: diameter)
                    drawCircle(slices: group, in: bounds, active: active)
                }
            case .bars: drawBars(slices: state.slices, in: rect, active: active)
            }
            return true
        }
        // Active wedges retain their color; inactive wedges follow light/dark appearance.
        image.isTemplate = false
        image.accessibilityDescription = state.toolTip(for: style)
        return image
    }

    private static func drawBars(slices: [GPUPieSlice], in rect: NSRect, active: NSColor) {
        guard !slices.isEmpty else {
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
            let outline = NSBezierPath(rect: NSRect(x: rect.midX - barWidth / 2, y: rect.minY + 2, width: barWidth, height: rect.height - 4))
            outline.lineWidth = 1
            outline.stroke()
            return
        }
        let width = CGFloat(slices.count) * (barWidth + barGap) - barGap
        let start = rect.midX - width / 2
        for (index, slice) in slices.enumerated() {
            (slice.active ? active : NSColor.labelColor.withAlphaComponent(0.23)).setFill()
            NSBezierPath(rect: NSRect(x: start + CGFloat(index) * (barWidth + barGap), y: rect.minY + 2, width: barWidth, height: rect.height - 4)).fill()
        }
    }

    private static func drawCircle(slices: [GPUPieSlice], in rect: NSRect, active: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.425
        let inactive = NSColor.labelColor.withAlphaComponent(0.23)
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
