import AppKit
import SwiftUI

private struct WindowGlassProvidedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var windowGlassProvided: Bool {
        get { self[WindowGlassProvidedKey.self] }
        set { self[WindowGlassProvidedKey.self] = newValue }
    }
}

/// Own the glass at the AppKit window boundary, with SwiftUI inside its contentView.
@MainActor final class GlassHostingController<Content: View>: NSViewController {
    private let hosting: NSHostingController<AnyView>
    private let followsContentSize: Bool

    init(rootView: Content, followsContentSize: Bool = false) {
        self.followsContentSize = followsContentSize
        hosting = NSHostingController(rootView: Self.hosted(rootView))
        super.init(nibName: nil, bundle: nil)
        if followsContentSize { hosting.sizingOptions = [.preferredContentSize] }
    }

    private static func hosted(_ rootView: Content) -> AnyView {
        AnyView(rootView.environment(\.windowGlassProvided, true)
            .background {
                // Keep the base calm even over bright windows; Glass supplies blur and its native edge.
                Color(nsColor: .windowBackgroundColor).opacity(0.55).ignoresSafeArea()
            })
    }

    func updateRootView(_ rootView: Content) { hosting.rootView = Self.hosted(rootView) }
    var contentSize: NSSize { hosting.sizeThatFits(in: NSSize(width: 1_000, height: 1_000)) }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard followsContentSize, viewController === hosting, let window = view.window else { return }
        let size = hosting.preferredContentSize
        if size.width > 0, size.height > 0, window.contentLayoutRect.size != size {
            window.setContentSize(size)
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(rootView:)") }

    override func loadView() {
        addChild(hosting)
        let surface: NSView
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // Regular glass softens the desktop behind the entire window, including gaps between panels.
            glass.style = .regular
            glass.cornerRadius = 20
            glass.contentView = hosting.view
            surface = glass
        } else { surface = compatibilitySurface() }
        #else
        surface = compatibilitySurface()
        #endif
        view = surface
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: surface.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
    }

    private func compatibilitySurface() -> NSView {
        let surface = NSVisualEffectView()
        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .followsWindowActiveState
        surface.addSubview(hosting.view)
        return surface
    }
}
