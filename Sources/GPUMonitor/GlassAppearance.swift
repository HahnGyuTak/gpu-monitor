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
    func monitorCard(radius: CGFloat = 12) -> some View { modifier(MonitorCardModifier(radius: radius)) }
}

/// Keep system button focus, keyboard activation and disabled states. Glass belongs to actions only.
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

private struct MonitorCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let radius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background(Color(nsColor: MonitorAppearance.surface), in: shape)
            .overlay(shape.strokeBorder(contrast == .increased ? Color.primary.opacity(0.5) : outlineColor.opacity(0.6)))
    }
}

struct DashboardBackdrop: View {
    var body: some View {
        Color(nsColor: MonitorAppearance.background).allowsHitTesting(false).accessibilityHidden(true)
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
                .frame(width: 26, height: 26)
        }.buttonStyle(.borderless).controlSize(.small).help(label).accessibilityLabel(label)
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
                Capsule().fill(outlineColor.opacity(0.55))
                Capsule().fill(accent).frame(width: geometry.size.width * (value.isFinite ? min(1, max(0, value)) : 0))
            }
        }.frame(height: 5)
    }
}
