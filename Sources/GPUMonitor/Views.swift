import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: Monitor
    @State private var settings = false
    @State private var adding = false
    @State private var filter = JobFilter.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { Color(nsColor: MonitorAppearance.iconColor(monitor.preferences.menuIconColor)) }
    private var busy: Bool { monitor.states.values.contains { $0.isLoading } || !monitor.deletingSessions.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                dashboard.opacity(settings ? 0 : 1).allowsHitTesting(!settings).disabled(settings).accessibilityHidden(settings)
                SettingsView(monitor: monitor).opacity(settings ? 1 : 0).allowsHitTesting(settings).disabled(!settings).accessibilityHidden(!settings)
            }
        }
        .frame(width: MonitorAppearance.dashboardSize.width, height: MonitorAppearance.dashboardSize.height)
        .background { DashboardBackdrop() }
        .font(.system(size: 13))
        .sheet(isPresented: $adding) { AddServerView(monitor: monitor).monitorTheme(monitor.preferences.menuIconColor) }
        .monitorTheme(monitor.preferences.menuIconColor)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: GPUPieIcon.image(for: GPUPieState(server: nil, slices: [
                GPUPieSlice(index: 0, active: true), GPUPieSlice(index: 1, active: true),
                GPUPieSlice(index: 2, active: false), GPUPieSlice(index: 3, active: true)
            ], status: nil), color: monitor.preferences.menuIconColor))
                .resizable().frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings ? "설정" : "GPU Monitor").font(.system(size: 19, weight: .semibold))
                Text(settings ? "나에게 맞는 모니터링" : "GPU와 학습 상태를 한눈에")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer(minLength: 8)
            MonitorGlassGroup {
                HStack(spacing: 8) {
                    GlassIconButton(symbol: monitor.paused ? "play.fill" : "pause.fill", label: monitor.paused ? "자동 조회 다시 시작" : "자동 조회 일시 정지", selected: monitor.paused) {
                        monitor.setPaused(!monitor.paused)
                    }
                    GlassIconButton(symbol: "arrow.clockwise", label: busy ? "새로고침 중" : "모든 서버 새로고침 · ⌘R") {
                        Task { await monitor.refresh() }
                    }.keyboardShortcut("r", modifiers: .command)
                        .disabled(busy || !monitor.preferences.servers.contains(where: \.enabled))
                    GlassIconButton(symbol: settings ? "xmark" : "gearshape", label: settings ? "설정 닫기 · ⌘," : "설정 · ⌘,", selected: settings) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { settings.toggle() }
                    }.keyboardShortcut(",", modifiers: .command)
                }
            }
        }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            MonitorGlassGroup {
                HStack(spacing: 12) {
                    MonitorSegmentedPicker(label: "작업 필터", options: JobFilter.allCases.map { ($0, $0.label) }, selection: $filter)
                    Button { adding = true } label: { Label("서버 추가", systemImage: "plus") }
                        .buttonStyle(MonitorButtonStyle()).fixedSize()
                        .keyboardShortcut("n", modifiers: .command).help("SSH 서버 추가 · ⌘N")
                }
            }.padding(.horizontal, 18).padding(.bottom, 14)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if monitor.preferences.servers.isEmpty { emptyState }
                    if filter != .all && !monitor.preferences.servers.isEmpty {
                        Text(filter == .running ? "실행 중인 작업만 표시합니다. GPU는 서버 전체 사용률입니다." : "벨을 켠 작업만 표시합니다. GPU는 서버 전체 사용률입니다.")
                            .font(.system(size: 11)).foregroundStyle(muted).padding(.horizontal, 4)
                    }
                    ForEach(monitor.preferences.servers) { server in
                        ServerCard(monitor: monitor, server: server, filter: filter)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            footer
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack").font(.system(size: 32, weight: .light)).foregroundStyle(accent)
                .frame(width: 70, height: 70).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            Text("첫 서버를 연결해 보세요").font(.system(size: 17, weight: .semibold))
            Text("기존 SSH 설정으로 GPU 사용률과\ntmux의 학습 진행 상황을 확인합니다.")
                .font(.system(size: 12)).foregroundStyle(muted).multilineTextAlignment(.center).lineSpacing(4)
            Button { adding = true } label: { Label("SSH 서버 추가", systemImage: "plus") }
                .buttonStyle(MonitorButtonStyle(selected: true)).padding(.top, 4)
        }.frame(maxWidth: .infinity).padding(.vertical, 48).monitorCard()
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: monitor.paused ? "pause.circle" : "arrow.triangle.2.circlepath")
                .foregroundStyle(accent)
            Text(monitor.paused ? "자동 조회 일시 정지" : "\(Int(monitor.preferences.interval))초마다 자동 조회")
            Spacer()
            if busy { ProgressView().controlSize(.mini); Text("갱신 중") }
            else { Text("핀: 메뉴바  ·  벨: 알림 감시") }
        }.font(.system(size: 11)).foregroundStyle(muted)
            .padding(.horizontal, 20).padding(.vertical, 13)
            .background(.bar)
    }
}
