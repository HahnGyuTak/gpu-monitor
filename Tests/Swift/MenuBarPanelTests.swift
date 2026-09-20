import AppKit

@main struct MenuBarPanelChecks {
    static func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }

    @MainActor static func main() {
        let size = NSSize(width: 520, height: 700)
        let screen = NSRect(x: 0, y: 40, width: 1440, height: 836)
        let centered = MenuBarPanel.placement(anchor: NSRect(x: 708, y: 876, width: 24, height: 24), visibleFrame: screen, contentSize: size)
        require(centered.size == size && centered.midX == 720 && centered.maxY == 868,
                "Keep the dashboard content size and the gap below the menu bar")
        print("PASS centered menu-bar placement and dashboard dimensions")

        for x: CGFloat in [0, 1416] {
            let frame = MenuBarPanel.placement(anchor: NSRect(x: x, y: 876, width: 24, height: 24), visibleFrame: screen, contentSize: size)
            require(screen.insetBy(dx: 8, dy: 8).contains(frame), "Clamp both horizontal screen edges")
        }
        print("PASS menu-bar anchors at both screen edges stay visible")

        let secondary = NSRect(x: -1920, y: -600, width: 1920, height: 1080)
        let secondaryFrame = MenuBarPanel.placement(anchor: NSRect(x: -120, y: 480, width: 80, height: 24), visibleFrame: secondary, contentSize: size)
        require(secondary.insetBy(dx: 8, dy: 8).contains(secondaryFrame) && secondaryFrame.size == size,
                "Place on the anchor's secondary display, including negative origins")
        print("PASS secondary display and negative screen coordinates")

        let shortScreen = NSRect(x: 1440, y: 48, width: 1024, height: 560)
        let compact = MenuBarPanel.placement(anchor: NSRect(x: 2240, y: 608, width: 120, height: 24), visibleFrame: shortScreen, contentSize: size)
        require(shortScreen.insetBy(dx: 8, dy: 8).contains(compact) && compact.height == 544 && compact.width == 520,
                "Short displays must keep the footer above the Dock instead of extending offscreen")
        print("PASS short display respects available height and Dock margin")
        print("4 Menu bar panel checks passed")
    }
}
