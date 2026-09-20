import AppKit

/// System surfaces and the user-selected accent; shared by AppKit and SwiftUI.
enum MonitorAppearance {
    static let dashboardSize = NSSize(width: 520, height: 700)
    static let minimumWindowSize = NSSize(width: 520, height: 420)

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }

    static let accent = adaptive(light: 0x245CD6, dark: 0x8AB4FF)
    static let background = NSColor.windowBackgroundColor
    static let surface = NSColor.controlBackgroundColor
    static let inset = NSColor.textBackgroundColor
    static let secondaryText = NSColor.secondaryLabelColor
    static let border = NSColor.separatorColor

    static func iconColor(_ selection: MenuIconColor) -> NSColor {
        switch selection {
        case .blue: return accent
        case .green: return NSColor(srgbRed: 0.08, green: 0.72, blue: 0.49, alpha: 1)
        case .orange: return adaptive(light: 0xCD610A, dark: 0xFFAD66)
        case .purple: return adaptive(light: 0x8051C7, dark: 0xC2A2FF)
        case .monochrome: return .labelColor
        }
    }
}
