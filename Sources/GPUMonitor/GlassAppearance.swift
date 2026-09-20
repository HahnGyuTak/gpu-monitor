import SwiftUI

private struct MonitorAccentKey: EnvironmentKey {
    static let defaultValue = Color(nsColor: MonitorAppearance.iconColor(.blue))
}

private struct MonitorIconColorKey: EnvironmentKey {
    static let defaultValue = MenuIconColor.blue
}

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

extension View {
    func monitorTheme(_ color: MenuIconColor) -> some View {
        let accent = Color(nsColor: MonitorAppearance.iconColor(color))
        return environment(\.monitorAccent, accent)
            .environment(\.monitorIconColor, color)
            .tint(accent)
    }

    func glassControl(radius: CGFloat = 18, selected: Bool = false) -> some View {
        modifier(GlassControlModifier(radius: radius, selected: selected))
    }

    func monitorCard(radius: CGFloat = 20) -> some View {
        modifier(MonitorCardModifier(radius: radius))
    }
}

/// Functional surfaces use native Liquid Glass; the data cards below use standard material.
private struct GlassControlModifier: ViewModifier {
    @Environment(\.monitorAccent) private var accent
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let radius: CGFloat
    let selected: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(selected ? accent.opacity(0.16) : nil).interactive(!reduceMotion),
                                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content.monitorCard(radius: radius)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? accent.opacity(0.5) : Color.clear))
    }
}

struct MonitorGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content

    @ViewBuilder var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 8) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

private struct MonitorCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if reduceTransparency { shape.fill(Color(nsColor: MonitorAppearance.surface)) }
            else { shape.fill(.regularMaterial) }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(
            contrast == .increased ? Color.primary.opacity(0.45) : Color.white.opacity(scheme == .dark ? 0.12 : 0.65),
            lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.035), radius: 9, y: 4)
    }
}

struct DashboardBackdrop: View {
    @Environment(\.monitorAccent) private var accent
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: MonitorAppearance.background)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [accent.opacity(0.10), .clear, accent.opacity(0.025)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlassIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 36, height: 36)
        }.buttonStyle(MonitorButtonStyle(selected: selected, icon: true))
            .help(label).accessibilityLabel(label)
    }
}

let muted = Color(nsColor: MonitorAppearance.secondaryText)
let inset = Color(nsColor: MonitorAppearance.inset)
let outlineColor = Color(nsColor: MonitorAppearance.border)

/// Floating actions share one treatment; embedded row actions use the same geometry without extra glass layers.
struct MonitorButtonStyle: ButtonStyle {
    var selected = false
    var icon = false
    var embedded = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(configuration: configuration, selected: selected, icon: icon, embedded: embedded)
    }

    private struct ButtonSurface: View {
        @Environment(\.monitorAccent) private var accent
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        let configuration: Configuration
        let selected: Bool
        let icon: Bool
        let embedded: Bool

        var body: some View {
            surface
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }

        @ViewBuilder private var surface: some View {
            if embedded { label }
            else { label.glassControl(radius: 18, selected: selected) }
        }

        private var label: some View {
            configuration.label
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .labelStyle(MonitorActionLabelStyle())
                .foregroundStyle(icon ? accent : Color.primary)
                .padding(.horizontal, icon ? 0 : 14)
                .frame(minWidth: icon ? 30 : nil, minHeight: embedded ? 30 : 36)
                .background(accent.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: embedded ? 9 : 18))
                .contentShape(RoundedRectangle(cornerRadius: embedded ? 9 : 18))
        }

        private var backgroundOpacity: Double {
            guard enabled else { return 0 }
            if configuration.isPressed { return 0.20 }
            if hovering { return 0.12 }
            return selected ? 0.10 : 0
        }
    }
}

private struct MonitorActionLabelStyle: LabelStyle {
    @Environment(\.monitorAccent) private var accent
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(accent)
            configuration.title
        }
    }
}

struct RowIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
        }.buttonStyle(MonitorButtonStyle(selected: selected, icon: true, embedded: true))
            .help(label).accessibilityLabel(label)
    }
}

struct MonitorSegmentedPicker<Value: Hashable>: View {
    @Environment(\.monitorAccent) private var accent
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title).frame(maxWidth: .infinity)
                }.buttonStyle(MonitorButtonStyle(selected: selection == value, embedded: true))
                    .accessibilityLabel(label + ": " + title)
                    .accessibilityValue(selection == value ? "선택됨" : "선택 안 됨")
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }.padding(4).glassControl(radius: 15)
            .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}

struct SectionHeading: View {
    @Environment(\.monitorAccent) private var accent
    let title: String
    let symbol: String
    var body: some View {
        Label { Text(title).foregroundStyle(Color.primary) } icon: { Image(systemName: symbol).foregroundStyle(accent) }
            .font(.system(size: 13, weight: .semibold))
    }
}

struct StatusMessage: View {
    @Environment(\.monitorAccent) private var accent
    let symbol: String
    let title: String
    var detail: String? = nil
    var warning = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(warning ? Color.orange : accent).frame(width: 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(muted).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true).padding(12)
            .background(warning ? Color.orange.opacity(0.07) : inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FractionBar: View {
    @Environment(\.monitorAccent) private var accent
    let value: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(outlineColor)
                Capsule().fill(accent.gradient).frame(width: geometry.size.width * (value.isFinite ? min(1, max(0, value)) : 0))
            }
        }.frame(height: 5)
    }
}
