import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var window: NSWindow?
    private var statusTimer: Timer?
    let monitor = Monitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.imageScaling = .scaleNone
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = MonitorAppearance.dashboardSize
        popover.contentViewController = NSHostingController(rootView:
            DashboardView(monitor: monitor, openWindow: { [weak self] in self?.showDashboard() })
                .frame(width: MonitorAppearance.dashboardSize.width, height: MonitorAppearance.dashboardSize.height))
        monitor.onChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
        // Age the icon even when a server stops returning snapshots.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }
        monitor.start()
        if CommandLine.arguments.contains("--show-window") { showDashboard() }
    }

    // Accessory apps also need the responder-chain Edit menu for text field and log shortcuts.
    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "GPU Monitor")
        appMenu.addItem(withTitle: "GPU Monitor 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "윈도우")
        let show = windowMenu.addItem(withTitle: "모니터 창 열기", action: #selector(showDashboard), keyEquivalent: "0")
        show.target = self
        windowMenu.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    private func updateStatusItem() {
        let state = monitor.menuGPUState
        let style = monitor.preferences.menuIconStyle
        statusItem.button?.image = GPUPieIcon.image(for: state, style: style, color: monitor.preferences.menuIconColor)
        statusItem.button?.title = " " + monitor.menuTitle
        statusItem.button?.toolTip = state.toolTip(for: style)
        statusItem.button?.setAccessibilityLabel(state.toolTip(for: style) + "\n" + monitor.menuTitle)
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func showDashboard() {
        popover?.performClose(nil)
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            let controller = NSHostingController(rootView: DashboardView(monitor: monitor))
            let dashboard = NSWindow(contentViewController: controller)
            dashboard.title = "GPU Monitor"
            dashboard.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            dashboard.isReleasedWhenClosed = false
            dashboard.isOpaque = false
            dashboard.backgroundColor = .clear
            dashboard.titlebarAppearsTransparent = true
            dashboard.contentMinSize = MonitorAppearance.minimumWindowSize
            dashboard.setContentSize(MonitorAppearance.dashboardSize)
            dashboard.center()
            dashboard.setFrameAutosaveName("GPUMonitorDashboard")
            dashboard.setFrameUsingName("GPUMonitorDashboard")
            dashboard.makeKeyAndOrderFront(nil)
            window = dashboard
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showDashboard() }
        return true
    }
}

@main struct GPUMonitorMain {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--probe") {
            guard CommandLine.arguments.count > index + 1 else {
                fputs("Usage: GPUMonitor --probe <ssh-alias>\n", stderr)
                exit(2)
            }
            let alias = CommandLine.arguments[index + 1]
            Task {
                do {
                    let (snapshot, container) = try await SSHProvider().collect(ServerConfig(alias: alias))
                    print("Connected: \(alias); container: \(container ?? "host")")
                    for gpu in snapshot.gpus { print("GPU \(gpu.index): \(gpu.name); utilization=\(gpu.utilization ?? -1)%; VRAM=\(gpu.memoryUsed ?? -1)/\(gpu.memoryTotal ?? -1) MiB") }
                    print("tmux: \(snapshot.panes.count) panes; active=\(snapshot.panes.filter(\.active).count); progress bars=\(snapshot.panes.filter { $0.progress != nil }.count)")
                    print("GPU PID mapping limited: \(snapshot.gpuPIDMappingLimited); errors: \(snapshot.errors)")
                    exit(snapshot.errors.isEmpty ? 0 : 2)
                } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
