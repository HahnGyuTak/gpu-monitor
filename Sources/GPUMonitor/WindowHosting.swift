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

    init(rootView: Content) {
        hosting = NSHostingController(rootView: AnyView(rootView
            .environment(\.windowGlassProvided, true)
            .background {
                // Keep the base calm even over bright windows; Glass still supplies blur and its native edge.
                Color(nsColor: .windowBackgroundColor).opacity(0.55).ignoresSafeArea()
            }))
        super.init(nibName: nil, bundle: nil)
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
