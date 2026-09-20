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
    @Environment(\.monitorAccent) private var accent
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent).frame(width: 34, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain).glassControl(radius: 17, selected: selected)
            .help(label).accessibilityLabel(label)
    }
}
