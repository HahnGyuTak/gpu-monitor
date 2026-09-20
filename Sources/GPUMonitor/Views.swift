import AppKit
import SwiftUI

private struct ServerLogTarget: Identifiable {
    let server: ServerConfig
    let pane: Pane
    var id: String { jobKey(server.id, pane.id) }
}

struct DashboardView: View {
    @ObservedObject var monitor: Monitor
    var openWindow: (() -> Void)? = nil
    @State private var settings = false
    @State private var adding = false
    @State private var filter = ServerFilter.all
    @State private var logTarget: ServerLogTarget?
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
        .background {
            MonitorSheet(isPresented: $adding, title: "SSH 서버 추가") { close in
                AddServerView(monitor: monitor, close: close).monitorTheme(monitor.preferences.menuIconColor)
            }.frame(width: 0, height: 0)
        }
        // A GPU becoming idle can remove its server from the filter while its log stays open.
        .sheet(item: $logTarget) { target in
            LogView(monitor: monitor, server: target.server, initialPane: target.pane)
                .monitorTheme(monitor.preferences.menuIconColor)
        }
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
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var dashboard: some View {
        // Age the running filter even when a server stops returning observations.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            serverDashboard(at: context.date)
        }
    }

    private func serverDashboard(at now: Date) -> some View {
        let servers = monitor.visibleServers(matching: filter, at: now)
        return VStack(spacing: 0) {
            if !monitor.preferences.servers.isEmpty {
                HStack(spacing: 10) {
                    MonitorSegmentedPicker(label: "서버 필터", options: ServerFilter.allCases.map { ($0, $0.label) }, selection: $filter)
                        .help(filter.summary)
                    Button { adding = true } label: { AccentLabel(title: "서버 추가", symbol: "plus") }
                        .monitorAction().fixedSize().keyboardShortcut("n", modifiers: .command)
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if monitor.preferences.servers.isEmpty { emptyState }
                    if !monitor.preferences.servers.isEmpty {
                        Text(filter.summary).font(.caption).foregroundStyle(muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if servers.isEmpty { filteredEmptyState }
                    }
                    ForEach(servers) { server in
                        ServerCard(monitor: monitor, server: server) { pane in
                            logTarget = ServerLogTarget(server: server, pane: pane)
                        }
                    }
                }.padding(12)
            }
            footer(visibleCount: servers.count)
        }
    }

    private var filteredEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if monitor.paused {
                StatusMessage(symbol: "pause.circle", title: "자동 조회가 일시 정지되어 있습니다",
                              detail: "조회를 다시 시작하면 선택한 조건의 서버를 표시합니다.")
                Button("조회 다시 시작") { monitor.setPaused(false) }.monitorAction()
            } else if filter == .running {
                StatusMessage(symbol: "cpu", title: "활성 GPU가 확인된 조회 서버가 없습니다",
                              detail: "최신 GPU 사용률이나 연산 프로세스가 확인되면 표시합니다.")
                Button("조회 서버 보기") { filter = .querying }.monitorAction()
            } else {
                StatusMessage(symbol: "network", title: "조회 중인 서버가 없습니다",
                              detail: "전체 목록의 서버 관리 메뉴에서 조회를 시작하세요.")
                Button("전체 서버 보기") { filter = .all }.monitorAction()
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).monitorSurface(.panel)
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

    private func footer(visibleCount: Int) -> some View {
        HStack(spacing: 6) {
            Text(monitor.paused ? "자동 조회 일시 정지" : "\(Int(monitor.preferences.interval))초마다 자동 조회")
            Spacer()
            if busy { ProgressView().controlSize(.mini).help("갱신 중") }
            Text(filter == .all ? "\(visibleCount)개 서버" : "\(visibleCount) / \(monitor.preferences.servers.count)개 서버")
                .monospacedDigit().accessibilityLabel("전체 \(monitor.preferences.servers.count)개 중 \(visibleCount)개 서버 표시")
        }.font(.caption).foregroundStyle(muted).padding(.horizontal, 16).padding(.vertical, 8)
    }
}
