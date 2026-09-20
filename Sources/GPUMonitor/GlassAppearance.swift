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

extension View {
    func monitorTheme(_ color: MenuIconColor) -> some View {
        let accent = Color(nsColor: MonitorAppearance.iconColor(color))
        return environment(\.monitorAccent, accent).environment(\.monitorIconColor, color).tint(accent)
    }
    func monitorAction(primary: Bool = false) -> some View { modifier(MonitorActionModifier(primary: primary)) }
    func monitorSheetPresentation() -> some View { modifier(MonitorSheetPresentation()) }
    func monitorSurface(_ layer: MonitorGlassLayer = .panel, radius: CGFloat = 14, selected: Bool = false) -> some View {
        background { MonitorGlassSurface(layer: layer, radius: radius, selected: selected) }
    }
}

private struct MonitorSheetPresentation: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 13.3, *) {
            if reduceTransparency { content.presentationBackground(Color(nsColor: .windowBackgroundColor)) }
            else { content.presentationBackground(.ultraThinMaterial) }
        } else { content }
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

/// The window owns the backdrop; content layers never stack another full-window material over it.
enum MonitorGlassLayer {
    case panel, well
}

struct MonitorGlassSurface: View {
    @Environment(\.monitorAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let layer: MonitorGlassLayer
    var radius: CGFloat = 14
    var selected = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    private var backing: Color { Color(nsColor: layer == .well ? .textBackgroundColor : .controlBackgroundColor) }

    var body: some View {
        material
            .overlay {
                if contrast == .increased { shape.strokeBorder(Color.primary.opacity(0.55), lineWidth: 1) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    @ViewBuilder private var material: some View {
        if reduceTransparency {
            shape.fill(backing)
                .overlay(shape.fill(selected ? accent.opacity(0.12) : .clear))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                shape.fill(Color.clear)
                    .glassEffect(Glass.regular
                        .tint(selected ? accent.opacity(0.12) : nil), in: shape)
                    .overlay(shape.inset(by: 1).fill(backing.opacity(layer == .well ? 0.58 : 0.38)))
            } else { compatibilityMaterial }
            #else
            compatibilityMaterial
            #endif
        }
    }

    private var compatibilityMaterial: some View {
        shape.fill(layer == .well ? .regularMaterial : .ultraThinMaterial)
            .overlay(shape.fill(selected ? accent.opacity(0.08) : .clear))
    }
}

/// Explicit behind-window blending is needed here; SwiftUI glass samples within its own window.
private struct WindowGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        return material
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}

struct DashboardBackdrop: View {
    @Environment(\.windowGlassProvided) private var provided
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else if provided { Color.clear }
            else { WindowGlassBackdrop() }
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
    @Environment(\.monitorAccent) private var accent
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focusedOption: Value?
    @State private var keyboardFocusVisible = false
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value

    @ViewBuilder var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency { glassPicker }
        else { nativePicker }
        #else
        nativePicker
        #endif
    }

    private var nativePicker: some View {
        Picker(label, selection: Binding(get: { selection }, set: {
            selection = $0
            focusedOption = $0
            keyboardFocusVisible = NSApp.currentEvent?.type == .keyDown
        })) {
            ForEach(options, id: \.0) { value, title in Text(title).tag(value) }
        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(label)
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var glassPicker: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(options, id: \.0) { value, title in
                    let selected = selection == value
                    Button {
                        selection = value
                        focusedOption = value
                        keyboardFocusVisible = NSApp.currentEvent?.type == .keyDown
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark").font(.caption2.weight(.semibold))
                                .foregroundStyle(enabled ? accent : Color(nsColor: .disabledControlTextColor))
                                .opacity(selected ? 1 : 0).accessibilityHidden(true)
                            Text(title).font(.callout.weight(selected ? .semibold : .regular))
                                .foregroundStyle(enabled ? Color.primary : Color(nsColor: .disabledControlTextColor))
                                .lineLimit(1)
                        }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).focusable(interactions: .edit)
                        .focused($focusedOption, equals: value)
                        .focusEffectDisabled(!keyboardFocusVisible)
                        .background {
                            if selected {
                                Capsule().fill(.clear)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                        }
                        .overlay {
                            if selected && contrast == .increased {
                                Capsule().strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                            }
                        }
                }
            }.padding(3)
                .glassEffect(.regular, in: .capsule)
        }
        // Keep a single-choice picker for VoiceOver, including its selected value and actions.
        .accessibilityRepresentation { nativePicker }
        .onChange(of: focusedOption) { value in
            // A mouse selection uses Glass alone; let macOS show focus for keyboard navigation.
            keyboardFocusVisible = value != nil && NSApp.currentEvent?.type == .keyDown
        }
        .onMoveCommand { direction in
            guard enabled, let current = options.firstIndex(where: { $0.0 == focusedOption }) else { return }
            let next: Int
            switch direction {
            case .left: next = max(0, current - 1)
            case .right: next = min(options.count - 1, current + 1)
            default: return
            }
            selection = options[next].0
            focusedOption = options[next].0
            keyboardFocusVisible = true
        }
    }
    #endif
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
        ProgressView(value: value.isFinite ? min(1, max(0, value)) : 0)
            .progressViewStyle(.linear).controlSize(.small).tint(value > 0 ? accent : .clear).frame(height: 5)
    }
}
