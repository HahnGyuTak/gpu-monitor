import AppKit

/// Neutral surfaces and one blue accent; shared by AppKit icons and SwiftUI.
enum MonitorAppearance {
    static let dashboardSize = NSSize(width: 520, height: 700)

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }

    static let accent = adaptive(light: 0x245CD6, dark: 0x8AB4FF)
    static let background = adaptive(light: 0xF3F4F6, dark: 0x191A1E)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x24252A)
    static let inset = adaptive(light: 0xF4F5F7, dark: 0x2C2D33)
    static let secondaryText = adaptive(light: 0x5A606B, dark: 0xADB3BE)
    static let border = adaptive(light: 0xDCDFE5, dark: 0x3B3D46)
}
