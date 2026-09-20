import AppKit
import SwiftUI

@MainActor private final class SheetSize: ObservableObject {
    @Published var height: CGFloat = 120
}

private struct ResizingForm: View {
    @ObservedObject var size: SheetSize
    var body: some View { Text("Form").frame(width: 240, height: size.height) }
}

@main struct MonitorSheetTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderFront(nil)
        defer { parent.close() }
        let coordinator = MonitorSheet<EmptyView>.Coordinator()
        let size = SheetSize()
        var cancellations = 0
        let root = AnyView(ResizingForm(size: size))
        coordinator.present(root, title: "Test form", on: parent) { cancellations += 1 }
        settle()
        guard let sheet = parent.attachedSheet else { fatalError("Form must remain a native attached sheet") }
        precondition(!sheet.isOpaque && sheet.backgroundColor == .clear && sheet.canBecomeKey && sheet.canBecomeMain)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            precondition(sheet.contentView is NSGlassEffectView, "Glass must own the sheet's root")
        }
        #endif
        precondition(abs(sheet.contentLayoutRect.height - 120) < 1, "Initial form must fit its content")
        coordinator.present(root, title: "Test form", on: parent) { cancellations += 1 }
        settle()
        precondition(parent.attachedSheet === sheet, "Polling must not replace an open form")
        print("PASS: native transparent sheet is retained across updates")

        size.height = 220
        settle()
        precondition(abs(sheet.contentLayoutRect.height - 220) < 1, "Docker/error content must resize the sheet")
        print("PASS: sheet follows content height")

        sheet.cancelOperation(nil)
        precondition(cancellations == 1, "Escape must request dismissal through the binding")
        coordinator.dismiss()
        coordinator.dismiss()
        settle()
        precondition(parent.attachedSheet == nil && !sheet.isVisible)
        precondition(cancellations == 1, "Dismissal must not send a second cancellation")
        coordinator.present(root, title: "Test form", on: parent) { cancellations += 1 }
        settle()
        precondition(parent.attachedSheet != nil && parent.attachedSheet !== sheet, "Form must reopen after dismissal")
        coordinator.dismiss()
        settle()
        print("PASS: cancel, idempotent teardown and reopening")
        print("MonitorSheet: 3 checks passed")
    }

    @MainActor private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
}
