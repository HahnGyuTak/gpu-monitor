import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: Monitor
    var openWindow: (() -> Void)? = nil
    @State private var settings = false
    @State private var adding = false
    @State private var filter = JobFilter.all
    private var busy: Bool { monitor.states.values.contains { $0.isLoading } || !monitor.deletingSessions.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                dashboard.opacity(settings ? 0 : 1).allowsHitTesting(!settings).disabled(settings).accessibilityHidden(settings)
                SettingsView(monitor: monitor).opacity(settings ? 1 : 0).allowsHitTesting(settings).disabled(!settings).accessibilityHidden(!settings)
            }
        }
        .frame(minWidth: MonitorAppearance.minimumWindowSize.width, minHeight: MonitorAppearance.minimumWindowSize.height)
        .background { DashboardBackdrop() }.font(.body)
        .sheet(isPresented: $adding) { AddServerView(monitor: monitor).monitorTheme(monitor.preferences.menuIconColor) }
        .monitorTheme(monitor.preferences.menuIconColor)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(settings ? "설정" : (openWindow == nil ? "서버" : "GPU Monitor")).font(.headline)
            Spacer(minLength: 8)
            MonitorGlassGroup {
                HStack(spacing: 8) {
                    if let openWindow {
                        Button(action: openWindow) { AccentLabel(title: "윈도우", symbol: "macwindow") }
                            .monitorAction().help("크기를 조절할 수 있는 모니터 창 열기")
                    }
                    GlassIconButton(symbol: monitor.paused ? "play.fill" : "pause.fill", label: monitor.paused ? "자동 조회 다시 시작" : "자동 조회 일시 정지", selected: monitor.paused) {
                        monitor.setPaused(!monitor.paused)
                    }.disabled(monitor.preferences.servers.isEmpty)
                    GlassIconButton(symbol: "arrow.clockwise", label: busy ? "새로고침 중" : "모든 서버 새로고침 · ⌘R") {
                        Task { await monitor.refresh() }
                    }.keyboardShortcut("r", modifiers: .command)
                        .disabled(busy || !monitor.preferences.servers.contains(where: \.enabled))
                    GlassIconButton(symbol: settings ? "chevron.left" : "gearshape", label: settings ? "서버로 돌아가기 · ⌘," : "설정 · ⌘,", selected: settings) {
                        settings.toggle()
                    }.keyboardShortcut(",", modifiers: .command)
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10).monitorSurface(.chrome, radius: 0)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            if !monitor.preferences.servers.isEmpty {
                HStack(spacing: 10) {
                    MonitorSegmentedPicker(label: "작업 필터", options: JobFilter.allCases.map { ($0, $0.label) }, selection: $filter)
                    Button { adding = true } label: { AccentLabel(title: "서버 추가", symbol: "plus") }
                        .monitorAction().fixedSize().keyboardShortcut("n", modifiers: .command)
                }.padding(.horizontal, 16).padding(.vertical, 10).monitorSurface(.chrome, radius: 0)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if monitor.preferences.servers.isEmpty { emptyState }
                    if filter != .all && !monitor.preferences.servers.isEmpty {
                        Text(filter == .running ? "실행 중인 작업 · GPU 수치는 서버 전체 기준" : "감시 중인 작업 · GPU 수치는 서버 전체 기준")
                            .font(.caption).foregroundStyle(muted)
                    }
                    ForEach(monitor.preferences.servers) { server in
                        ServerCard(monitor: monitor, server: server, filter: filter)
                    }
                }.padding(12)
            }
            footer
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("등록된 서버가 없습니다").font(.headline)
            Text("SSH 서버를 추가해 GPU와 tmux 작업을 확인하세요.")
                .font(.callout).foregroundStyle(muted).multilineTextAlignment(.center)
            Button { adding = true } label: { Label("서버 추가", systemImage: "plus") }
                .monitorAction(primary: true).keyboardShortcut("n", modifiers: .command)
        }.frame(maxWidth: .infinity).padding(.vertical, 32).monitorSurface(.panel)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(monitor.paused ? "자동 조회 일시 정지" : "\(Int(monitor.preferences.interval))초마다 자동 조회")
            Spacer()
            if busy { ProgressView().controlSize(.mini); Text("갱신 중") }
            else { Text("\(monitor.preferences.servers.count)개 서버") }
        }.font(.caption).foregroundStyle(muted).padding(.horizontal, 16).padding(.vertical, 8).monitorSurface(.chrome, radius: 0)
    }
}
