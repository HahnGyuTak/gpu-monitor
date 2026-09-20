import AppKit

/// A transient menu-bar window with the same content and material as the dashboard window.
@MainActor final class MenuBarPanel: NSPanel, NSWindowDelegate {
    private weak var anchorWindow: NSWindow?
    private var localClicks: Any?
    private var globalClicks: Any?
    private var appDeactivation: NSObjectProtocol?
    private var dismissing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(content: NSViewController) {
        super.init(contentRect: NSRect(origin: .zero, size: MonitorAppearance.dashboardSize),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        title = "GPU Monitor · 메뉴바"
        contentViewController = content
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isMovable = false
        delegate = self
    }

    func show(anchoredTo button: NSView) {
        guard let anchor = button.window, let screen = anchor.screen ?? NSScreen.main else { return }
        anchorWindow = anchor
        let anchorRect = anchor.convertToScreen(button.convert(button.bounds, to: nil))
        setFrame(Self.placement(anchor: anchorRect, visibleFrame: screen.visibleFrame,
                                contentSize: MonitorAppearance.dashboardSize), display: false)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        startDismissalObservers()
    }

    func dismiss() {
        // A sheet owns its confirmation/cancellation; keep its parent alive while it is open.
        guard isVisible, attachedSheet == nil, !dismissing else { return }
        dismissing = true
        stopDismissalObservers()
        orderOut(nil)
        anchorWindow = nil
        dismissing = false
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
    override func performClose(_ sender: Any?) { dismiss() }

    func windowDidResignKey(_ notification: Notification) {
        guard attachedSheet == nil else { return }
        dismiss()
    }

    private func startDismissalObservers() {
        stopDismissalObservers()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClicks = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self, let clickedWindow = event.window else { return event }
            // Status-button clicks run the toggle action. Menus and sheets manage their own dismissal.
            if clickedWindow !== self, clickedWindow !== self.anchorWindow,
               clickedWindow.sheetParent !== self, clickedWindow.level < .popUpMenu {
                self.dismiss()
            }
            return event
        }
        // Mouse-only monitoring does not capture keys or require Accessibility permission.
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in self?.dismiss() }
        appDeactivation = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func stopDismissalObservers() {
        if let localClicks { NSEvent.removeMonitor(localClicks) }
        if let globalClicks { NSEvent.removeMonitor(globalClicks) }
        if let appDeactivation { NotificationCenter.default.removeObserver(appDeactivation) }
        localClicks = nil
        globalClicks = nil
        appDeactivation = nil
    }

    /// AppKit screen coordinates can be negative on secondary displays.
    static func placement(anchor: NSRect, visibleFrame: NSRect, contentSize: NSSize) -> NSRect {
        let margin: CGFloat = 8
        let available = visibleFrame.insetBy(dx: margin, dy: margin)
        let size = NSSize(width: min(contentSize.width, max(1, available.width)),
                          height: min(contentSize.height, max(1, available.height)))
        let x = min(max(anchor.midX - size.width / 2, available.minX), available.maxX - size.width)
        let top = min(anchor.minY - margin, available.maxY)
        let y = max(available.minY, min(top - size.height, available.maxY - size.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}
