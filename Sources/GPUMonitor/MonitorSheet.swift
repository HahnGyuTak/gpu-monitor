import AppKit
import SwiftUI

/// Keep native sheet modality while owning the Glass at the sheet window's root.
struct MonitorSheet<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder var content: (@escaping () -> Void) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SheetAnchor { SheetAnchor() }

    func updateNSView(_ view: SheetAnchor, context: Context) {
        let binding = $isPresented
        // The new hosting root reads system accessibility settings itself. Do not copy the
        // parent's entire environment: native sheet modality disables that parent's controls.
        let root = AnyView(content { binding.wrappedValue = false }
            .environment(\.colorScheme, context.environment.colorScheme))
        let coordinator = context.coordinator
        view.updatePresentation = { [weak view] in
            if binding.wrappedValue, let parent = view?.window {
                coordinator.present(root, title: title, on: parent) { binding.wrappedValue = false }
            } else { coordinator.dismiss() }
        }
        // Presentation changes window/focus state; do it after the SwiftUI update finishes.
        DispatchQueue.main.async { [weak view] in view?.updatePresentation?() }
    }

    static func dismantleNSView(_ view: SheetAnchor, coordinator: Coordinator) {
        view.updatePresentation = nil
        coordinator.dismiss()
    }

    final class SheetAnchor: NSView {
        var updatePresentation: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.updatePresentation?() }
        }
    }

    @MainActor final class Coordinator {
        private var sheet: GlassSheetWindow?
        private var controller: GlassHostingController<AnyView>?

        func present(_ root: AnyView, title: String, on parent: NSWindow, close: @escaping () -> Void) {
            if let controller { controller.updateRootView(root); return }
            guard parent.attachedSheet == nil else { return }
            let hosting = GlassHostingController(rootView: root, followsContentSize: true)
            let window = GlassSheetWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentViewController = hosting
            window.title = title
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = parent.level
            window.closeSheet = close
            window.setContentSize(hosting.contentSize)
            controller = hosting
            sheet = window
            parent.beginSheet(window) { [weak self, weak window] _ in
                guard let self, self.sheet === window else { return }
                self.sheet = nil
                self.controller = nil
                window?.orderOut(nil)
                close()
            }
        }

        func dismiss() {
            guard let window = sheet else { return }
            sheet = nil
            controller = nil
            window.closeSheet = nil
            window.sheetParent?.endSheet(window)
            window.orderOut(nil)
        }
    }
}

private final class GlassSheetWindow: NSPanel {
    var closeSheet: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { closeSheet?() }
    override func performClose(_ sender: Any?) { closeSheet?() }
}
