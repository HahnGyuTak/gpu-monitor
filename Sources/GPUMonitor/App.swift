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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.imageScaling = .scaleNone
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 480, height: 660)
        popover.contentViewController = NSHostingController(rootView: DashboardView(monitor: monitor))
        monitor.onChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
        // Age the icon even when a server stops returning snapshots.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }
        monitor.start()
        if CommandLine.arguments.contains("--show-window") { showDashboard() }
    }

    private func updateStatusItem() {
        let state = monitor.menuGPUState
        statusItem.button?.image = GPUPieIcon.image(for: state)
        statusItem.button?.title = " " + monitor.menuTitle
        statusItem.button?.toolTip = state.toolTip
        statusItem.button?.setAccessibilityLabel(state.toolTip + "\n" + monitor.menuTitle)
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showDashboard() {
        let view = NSHostingController(rootView: DashboardView(monitor: monitor))
        window = NSWindow(contentViewController: view)
        window?.title = "GPU Monitor"
        window?.styleMask = [.titled, .closable, .miniaturizable]
        window?.setContentSize(NSSize(width: 480, height: 660))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
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
