import AppKit
import SwiftUI

private struct MonitorAccentKey: EnvironmentKey {
    static let defaultValue = Color(nsColor: MonitorAppearance.iconColor(.blue))
}
private struct MonitorIconColorKey: EnvironmentKey { static let defaultValue = MenuIconColor.blue }

extension EnvironmentValues {
    var monitorAccent: Color {
        get { self[MonitorAccentKey.self] }
        set { self[MonitorAccentKey.self] = newValue }
    }
    var monitorIconColor: MenuIconColor {
        get { self[MonitorIconColorKey.self] }
        set { self[MonitorIconColorKey.self] = newValue }
    }
}

let muted = Color.secondary
let inset = Color(nsColor: MonitorAppearance.inset)
let outlineColor = Color(nsColor: MonitorAppearance.border)

extension View {
    func monitorTheme(_ color: MenuIconColor) -> some View {
        let accent = Color(nsColor: MonitorAppearance.iconColor(color))
        return environment(\.monitorAccent, accent).environment(\.monitorIconColor, color).tint(accent)
    }
    func monitorAction(primary: Bool = false) -> some View { modifier(MonitorActionModifier(primary: primary)) }
    func monitorSurface(_ layer: MonitorGlassLayer = .panel, radius: CGFloat = 14, selected: Bool = false) -> some View {
        background { MonitorGlassSurface(layer: layer, radius: radius, selected: selected) }
    }
}

/// Keep native focus, keyboard activation and disabled states on glass controls.
private struct MonitorActionModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let primary: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            if primary { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass).tint(nil) }
        } else { fallback(content) }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if primary { content.buttonStyle(.borderedProminent) }
        else { content.buttonStyle(.bordered) }
    }
}

struct MonitorGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 8) { content() }
        } else { content() }
        #else
        content()
        #endif
    }
}

/// Density belongs to the background, never to the text or its containing view.
enum MonitorGlassLayer {
    case canvas, chrome, panel, well

    var backingOpacity: Double {
        switch self {
        case .canvas: return 0.12
        case .chrome: return 0.22
        case .panel: return 0.34
        case .well: return 0.58
        }
    }
}

struct MonitorGlassSurface: View {
    @Environment(\.monitorAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let layer: MonitorGlassLayer
    var radius: CGFloat = 14
    var selected = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    private var backing: Color {
        Color(nsColor: layer == .well ? MonitorAppearance.inset : MonitorAppearance.background)
    }

    var body: some View {
        ZStack {
            material
            // A denser neutral backing protects numerals and log text from the scene behind the window.
            shape.fill(backing.opacity(reduceTransparency ? 1 : layer.backingOpacity))
            if selected {
                shape.fill(LinearGradient(colors: [accent.opacity(0.10), accent.opacity(0.025), accent.opacity(0.07)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                if !reduceTransparency && (layer == .panel || layer == .well) {
                    // Overlapping translucent bands fade inward, like color held in the glass edge.
                    // No blur filter is needed, so native and compatibility renders retain the same falloff.
                    ForEach(1...8, id: \.self) { band in
                        shape.strokeBorder(LinearGradient(colors: [
                            accent.opacity(scheme == .dark ? 0.026 : 0.018),
                            Color.white.opacity(0.01), accent.opacity(0.015)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: CGFloat(band * 2))
                    }
                }
            }
            if layer != .canvas {
                shape.strokeBorder(LinearGradient(colors: [
                    Color.white.opacity(scheme == .dark ? 0.25 : 0.78),
                    selected ? accent.opacity(0.20) : Color.white.opacity(0.06),
                    Color.white.opacity(scheme == .dark ? 0.10 : 0.40)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            if contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(layer == .panel && !reduceTransparency ? (scheme == .dark ? 0.18 : 0.07) : 0), radius: 5, y: 2)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    @ViewBuilder private var material: some View {
        if reduceTransparency { shape.fill(backing) }
        else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                shape.fill(Color.clear)
                    .glassEffect(.regular.tint(selected ? accent.opacity(0.14) : nil), in: shape)
            } else { compatibilityMaterial }
            #else
            compatibilityMaterial
            #endif
        }
    }

    private var compatibilityMaterial: some View {
        shape.fill(layer == .well ? .thickMaterial : .regularMaterial)
    }
}

/// A real behind-window material lets the desktop participate in the glass canvas.
private struct WindowGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}

struct DashboardBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if !reduceTransparency { WindowGlassBackdrop() }
            MonitorGlassSurface(layer: .canvas, radius: 0)
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlassIconButton: View {
    @Environment(\.monitorAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body)
                .foregroundStyle(enabled ? accent : Color(nsColor: .disabledControlTextColor)).frame(width: 18, height: 20)
        }.monitorAction().help(label).accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RowIconButton: View {
    @Environment(\.monitorAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(enabled ? accent : Color(nsColor: .disabledControlTextColor))
                .frame(width: 16, height: 18)
        }.monitorAction().controlSize(.small).help(label).accessibilityLabel(label)
    }
}

struct MonitorSegmentedPicker<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.0) { value, title in Text(title).tag(value) }
        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(label)
            .monitorSurface(.chrome, radius: 7)
    }
}

struct AccentLabel: View {
    @Environment(\.monitorAccent) private var accent
    let title: String
    let symbol: String
    var body: some View {
        Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(accent) }
    }
}

struct SectionHeading: View {
    let title: String
    let symbol: String
    var body: some View { AccentLabel(title: title, symbol: symbol).font(.headline) }
}

struct StatusMessage: View {
    @Environment(\.monitorAccent) private var accent
    let symbol: String
    let title: String
    var detail: String? = nil
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(warning ? Color.orange : accent).frame(width: 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(muted).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
    }
}

struct FractionBar: View {
    @Environment(\.monitorAccent) private var accent
    let value: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.thinMaterial)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                Capsule().fill(accent)
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)))
                    .frame(width: geometry.size.width * (value.isFinite ? min(1, max(0, value)) : 0))
            }
        }.frame(height: 5)
    }
}
