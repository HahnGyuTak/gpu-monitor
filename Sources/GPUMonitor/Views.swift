import AppKit
import SwiftUI

private let accent = Color(nsColor: NSColor(name: nil) { appearance in
    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(calibratedRed: 0.30, green: 0.87, blue: 0.74, alpha: 1)
    }
    return NSColor(calibratedRed: 0.02, green: 0.43, blue: 0.37, alpha: 1)
})
private let muted = Color.secondary

struct DashboardView: View {
    @ObservedObject var monitor: Monitor
    @State private var settings = false
    @State private var adding = false
    @State private var filter = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cpu.fill").font(.system(size: 23)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPU Monitor").font(.system(size: 17, weight: .semibold))
                    Text(monitor.paused ? "모니터링 일시 정지" : "REMOTE COMPUTE").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(muted).tracking(1.8)
                }
                Spacer()
                Button { monitor.paused.toggle(); monitor.save() } label: { Image(systemName: monitor.paused ? "play.fill" : "pause.fill") }
                    .help(monitor.paused ? "다시 시작" : "조회 일시 정지")
                Button { Task { await monitor.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("지금 새로고침")
                    .disabled(monitor.states.values.contains { $0.isLoading } || !monitor.deletingSessions.isEmpty)
                Button { settings.toggle() } label: { Image(systemName: settings ? "xmark" : "gearshape") }.help("설정")
            }
            .buttonStyle(.borderless).padding(20)
            Divider().opacity(0.5)
            if settings { SettingsView(monitor: monitor) }
            else {
                HStack {
                    Picker("보기", selection: $filter) {
                        Text("모든 pane").tag(0)
                        Text("실행 중").tag(1)
                        Text("감시 중").tag(2)
                    }.pickerStyle(.segmented).labelsHidden()
                    Button { adding = true } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help("SSH 서버 추가")
                }.padding(.horizontal, 18).padding(.vertical, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if monitor.preferences.servers.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "server.rack").font(.system(size: 30)).foregroundStyle(accent)
                                Text("SSH 서버를 추가하세요").font(.headline)
                                Text("기존 SSH 키와 설정을 사용합니다.").foregroundStyle(muted)
                                Button("서버 추가") { adding = true }
                            }.frame(maxWidth: .infinity).padding(.vertical, 60)
                        }
                        ForEach(monitor.preferences.servers) { server in
                            ServerCard(monitor: monitor, server: server, filter: filter)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 16)
                }
                Divider().opacity(0.5)
                HStack(spacing: 6) {
                    Circle().fill(monitor.paused ? Color.orange : accent).frame(width: 5, height: 5)
                    Text(monitor.paused ? "일시 정지" : "\(Int(monitor.preferences.interval))초 간격 · SSH 연결")
                    Spacer()
                    Text("핀: 메뉴바  ·  벨: 감시")
                }.font(.system(size: 10)).foregroundStyle(muted).padding(14)
            }
        }
        .frame(width: 480, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .sheet(isPresented: $adding) { AddServerView(monitor: monitor) }
    }
}

private struct ServerCard: View {
    @ObservedObject var monitor: Monitor
    let server: ServerConfig
    let filter: Int
    @State private var expanded = true
    var state: ServerViewState { monitor.states[server.id] ?? ServerViewState() }
    var isMenuServer: Bool { monitor.menuServer?.id == server.id }
    var jobs: [JobObservation] {
        state.jobs.values.filter {
            switch filter {
            case 1: return $0.state == .running
            case 2: return monitor.preferences.watched.contains(jobKey(server.id, $0.pane.id))
            default: return $0.state != .missing || monitor.preferences.watched.contains(jobKey(server.id, $0.pane.id)) || monitor.preferences.selected == jobKey(server.id, $0.pane.id)
            }
        }.sorted {
            if ($0.state == .running) != ($1.state == .running) { return $0.state == .running }
            if $0.pane.session != $1.pane.session { return $0.pane.session < $1.pane.session }
            return (Int($0.pane.window) ?? 0, Int($0.pane.index) ?? 0) < (Int($1.pane.window) ?? 0, Int($1.pane.index) ?? 0)
        }
    }
    var sessions: [String] {
        var seen = Set<String>()
        return jobs.map { $0.pane.session }.filter { seen.insert($0).inserted }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold))
                }.buttonStyle(.plain)
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    let gpuState = monitor.gpuState(for: server)
                    Image(nsImage: GPUPieIcon.image(for: gpuState))
                        .resizable().frame(width: 22, height: 22)
                        .help(gpuState.toolTip).accessibilityLabel(gpuState.toolTip)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.alias).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(server.alias)
                    if let container = state.resolvedContainer { Text("Docker · \(container)").font(.system(size: 10)).foregroundStyle(muted) }
                }
                Spacer()
                if state.isLoading { ProgressView().controlSize(.mini) }
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    if let updated = state.updatedAt {
                        Text("\(max(0, Int(Date().timeIntervalSince(updated))))초 전").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                    }
                }
                Button { monitor.selectMenuServer(server.id) } label: {
                    Label("메뉴바", systemImage: isMenuServer ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10, weight: isMenuServer ? .semibold : .regular))
                        .fixedSize()
                }.buttonStyle(.borderless).foregroundStyle(isMenuServer ? accent : muted)
                    .help("이 서버의 GPU 요약을 메뉴바에 표시")
                    .accessibilityLabel("\(server.alias) 메뉴바에 표시")
                    .accessibilityValue(isMenuServer ? "선택됨" : "선택 안 됨")
                Menu {
                    Button(server.enabled ? "서버 조회 중지" : "서버 조회 시작") {
                        if let i = monitor.preferences.servers.firstIndex(where: { $0.id == server.id }) {
                            monitor.preferences.servers[i].enabled.toggle(); monitor.save()
                            Task { await monitor.refresh() }
                        }
                    }
                    Button("서버 제거", role: .destructive) { monitor.remove(server.id) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18)
            }
            if expanded {
                if !server.enabled { Text("조회가 중지되었습니다. 아래는 마지막 확인 상태입니다.").font(.caption).foregroundStyle(.orange) }
                if let error = state.error {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("연결 끊김 · 마지막 상태 유지", systemImage: "wifi.exclamationmark").font(.system(size: 11, weight: .semibold))
                        Text(error).font(.system(size: 10)).textSelection(.enabled)
                    }.foregroundStyle(.orange).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                if let snapshot = state.snapshot {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(snapshot.gpus) { gpu in GPUCard(gpu: gpu) }
                    }.opacity(state.error == nil && server.enabled ? 1 : 0.5)
                    if snapshot.gpus.isEmpty { Text("GPU 정보를 읽을 수 없습니다.").font(.caption).foregroundStyle(muted) }
                    if snapshot.gpuPIDMappingLimited { Label("컨테이너 PID 차이로 GPU–pane 연결이 제한됩니다.", systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(muted) }
                    ForEach(snapshot.errors, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(.orange).textSelection(.enabled) }
                    HStack {
                        Text("TMUX").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                        Spacer()
                        Text("\(snapshot.panes.count) panes · \(snapshot.panes.filter(\.active).count) 실행 중").font(.system(size: 10))
                        Button { Task { await monitor.refresh(serverID: server.id) } } label: {
                            Image(systemName: "arrow.clockwise")
                        }.buttonStyle(.borderless).help("이 서버의 tmux 목록 갱신")
                            .accessibilityLabel("\(server.alias) tmux 목록 갱신")
                            .disabled(!server.enabled || state.isLoading || monitor.deletingSessions[server.id] != nil)
                    }.foregroundStyle(muted).padding(.top, 3)
                    if let message = monitor.sessionMessages[server.id] {
                        HStack(alignment: .top) {
                            Text(message).font(.system(size: 10)).textSelection(.enabled)
                            Spacer(minLength: 4)
                            if monitor.deletingSessions[server.id] == nil {
                                Button { monitor.sessionMessages.removeValue(forKey: server.id) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("메시지 닫기")
                            }
                        }.foregroundStyle(muted)
                    }
                    if sessions.isEmpty { Text(filter == 2 ? "pane의 벨을 눌러 감시 대상을 선택하세요." : "표시할 tmux pane이 없습니다.").font(.caption).foregroundStyle(muted).padding(.vertical, 8) }
                    ForEach(sessions, id: \.self) { session in
                        SessionSection(monitor: monitor, server: server, session: session, jobs: jobs.filter { $0.pane.session == session }, connected: state.error == nil && server.enabled)
                    }
                } else if state.error == nil {
                    Text("GPU와 tmux 상태를 읽고 있습니다…").font(.caption).foregroundStyle(muted).padding(.vertical, 16)
                }
            }
        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isMenuServer ? accent.opacity(0.35) : Color.primary.opacity(0.06)))
    }
}

private struct GPUCard: View {
    let gpu: GPU
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("GPU \(gpu.index)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(muted)
                Spacer()
                Text(gpu.utilization.map { "\(Int($0))%" } ?? "N/A").font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(accent)
            }
            Text(gpu.shortName).font(.system(size: 11, weight: .medium)).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(accent.opacity(0.75)).frame(width: geo.size.width * min(1, max(0, (gpu.utilization ?? 0) / 100)))
                }
            }.frame(height: 3)
            HStack(spacing: 2) {
                Text("VRAM \(gpu.memoryUsed.map { String(format: "%.1f", $0 / 1024) } ?? "—") / \(gpu.memoryTotal.map { String(format: "%.0f", $0 / 1024) } ?? "—") GiB")
                Spacer(minLength: 0)
                Text(gpu.temperature.map { "\(Int($0))°" } ?? "—")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
        }.padding(10).background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SessionSection: View {
    @ObservedObject var monitor: Monitor
    let server: ServerConfig
    let session: String
    let jobs: [JobObservation]
    let connected: Bool
    @State private var expanded = false
    @State private var deletionCandidate: TmuxSession?
    var info: TmuxSession? {
        monitor.states[server.id]?.snapshot?.sessions?.first { $0.name == session }
    }
    var busy: Bool { monitor.deletingSessions[server.id] != nil || monitor.states[server.id]?.isLoading == true }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        if jobs.count > 1 { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9)) }
                        Text(session).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text("\(info?.paneIDs.count ?? jobs.count) panes").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                    }.padding(.vertical, 3)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                if info?.canDelete == true { Text("비어 있음").font(.system(size: 9)).foregroundStyle(muted) }
                if monitor.deletingSessions[server.id] == info?.id && info != nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Button { deletionCandidate = info } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(muted)
                        .disabled(!connected || busy || info?.canDelete != true)
                        .help(info?.reason ?? "목록을 갱신하여 세션 상태를 확인하세요.")
                        .accessibilityLabel("\(session) 빈 tmux 세션 삭제")
                }
            }
            ForEach(jobs, id: \.pane.id) { job in
                if jobs.count == 1 || expanded || job.state == .running || monitor.preferences.watched.contains(jobKey(server.id, job.pane.id)) || monitor.preferences.selected == jobKey(server.id, job.pane.id) {
                    JobRow(monitor: monitor, server: server, job: job, connected: connected)
                }
            }
        }
        .alert("tmux 세션을 삭제할까요?", isPresented: Binding(get: { deletionCandidate != nil }, set: { if !$0 { deletionCandidate = nil } }), presenting: deletionCandidate) { candidate in
            Button("취소", role: .cancel) { deletionCandidate = nil }
            Button("세션 삭제", role: .destructive) {
                Task { await monitor.deleteSession(candidate, server: server) }
                deletionCandidate = nil
            }
        } message: { candidate in
            Text("\(server.alias) · \(candidate.name)\n\(candidate.paneIDs.count)개 pane과 화면 기록이 사라집니다. 삭제 직전에 실행 중인 작업과 연결된 클라이언트가 없는지 다시 확인합니다.")
        }
    }
}

private struct JobRow: View {
    @ObservedObject var monitor: Monitor
    let server: ServerConfig
    let job: JobObservation
    let connected: Bool
    @State private var logs = false
    var key: String { jobKey(server.id, job.pane.id) }
    var isPinned: Bool { monitor.preferences.selected == key }
    var isWatched: Bool { monitor.preferences.watched.contains(key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(job.state == .running ? accent : (job.state == .failed ? Color.red : Color.gray)).frame(width: 5, height: 5)
                Text(job.pane.title).font(.system(size: 11, weight: .medium)).lineLimit(1).help(job.pane.title)
                Spacer(minLength: 4)
                Button { monitor.pin(server: server.id, pane: job.pane.id) } label: { Image(systemName: isPinned ? "pin.fill" : "pin") }.foregroundStyle(isPinned ? accent : muted).help("메뉴바에 표시")
                Button { monitor.watch(server: server.id, pane: job.pane.id) } label: { Image(systemName: isWatched ? "bell.fill" : "bell") }.foregroundStyle(isWatched ? accent : muted).help("이 pane 감시 · 시스템 알림은 설정에서 활성화")
                Button { logs = true } label: { Image(systemName: "text.alignleft") }.foregroundStyle(muted).help("로그 미리보기")
            }.buttonStyle(.borderless)
            HStack(spacing: 5) {
                Text(job.pane.location).font(.system(size: 9, design: .monospaced))
                Text("· \(job.state.label)").font(.system(size: 9))
                Spacer()
                if job.state == .running {
                    Text(job.pane.gpuIDs.isEmpty ? "GPU 연결 미확인" : "GPU " + job.pane.gpuIDs.compactMap { id in monitor.states[server.id]?.snapshot?.gpus.first { $0.id == id }.map { String($0.index) } }.joined(separator: ", ")).font(.system(size: 9))
                }
            }.foregroundStyle(muted)
            if let progress = job.progress, job.state == .running {
                HStack {
                    Text("\(progress.percent)%").font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("\(progress.step)/\(progress.total)").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                    Spacer()
                    Text("\(progress.etaSource == "estimate" ? "≈ " : "")ETA \(durationText(progress.etaSeconds))").font(.system(size: 10, design: .monospaced))
                }
                ProgressView(value: progress.fraction).tint(accent)
                Text("현재 \(progress.scope == "epoch" ? "epoch" : "표시 단계") · \(progress.label)").font(.system(size: 9)).foregroundStyle(muted).lineLimit(1).help("로그의 현재 진행 막대입니다. 전체 학습 진행률과 다를 수 있습니다.")
                if job.lastProgressAt == nil { Text("로그 시각 미확인 · 다음 진행 변화를 기다리는 중").font(.system(size: 9)).foregroundStyle(muted) }
                else if let last = job.lastProgressAt, Date().timeIntervalSince(last) > 120 { Text("진행률이 2분 이상 갱신되지 않았습니다.").font(.system(size: 9)).foregroundStyle(.orange) }
            } else if job.state == .running { Text("진행률을 기다리는 중 · \(job.pane.workers.first?.name ?? job.pane.command)").font(.system(size: 10)).foregroundStyle(muted) }
            if let error = job.pane.captureError { Text("화면 읽기 실패: \(error)").font(.system(size: 9)).foregroundStyle(.orange) }
        }.padding(10).background(isPinned ? accent.opacity(0.07) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8)).opacity(connected ? 1 : 0.5)
            .sheet(isPresented: $logs) { LogView(server: server, pane: job.pane) }
    }
}

private struct AddServerView: View {
    @ObservedObject var monitor: Monitor
    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""
    @State private var container = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSH 서버 추가").font(.title2.bold())
            Text("등록된 SSH 별칭을 선택하거나 직접 입력하세요.").font(.caption).foregroundStyle(muted)
            HStack {
                TextField("별칭 또는 user@host", text: $alias)
                Menu("SSH 설정") { ForEach(monitor.aliases, id: \.self) { name in Button(name) { alias = name } } }.frame(width: 100)
            }
            TextField("컨테이너 · 비워두면 자동 감지", text: $container)
            Text("Docker RemoteCommand를 자동 인식합니다. SSH 호스트를 직접 조회하려면 host를 입력하세요. SSH 키 인증과 알려진 호스트를 사용합니다.").font(.caption).foregroundStyle(muted)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("연결") {
                    error = monitor.add(alias: alias, container: container)
                    if error == nil { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(alias.isEmpty)
            }
        }.padding(24).frame(width: 420)
    }
}

private struct SettingsView: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("모니터링 설정").font(.headline)
            Picker("조회 간격", selection: Binding(get: { monitor.preferences.interval }, set: { monitor.preferences.interval = $0; monitor.save() })) {
                Text("5초").tag(5.0); Text("10초").tag(10.0); Text("30초").tag(30.0); Text("60초").tag(60.0)
            }
            Toggle("간결한 메뉴바 표시", isOn: Binding(get: { monitor.preferences.compact }, set: { monitor.preferences.compact = $0; monitor.save() }))
            Divider()
            Toggle("macOS 알림", isOn: Binding(get: { monitor.preferences.notifications }, set: { monitor.setNotifications($0) }))
            Text("벨을 켠 pane에서 새 오류 로그·프로세스 종료·pane 소멸을 감지합니다. 처음 연결할 때의 과거 로그는 알리지 않습니다.").font(.caption).foregroundStyle(muted)
            if let message = monitor.notificationMessage { Text(message).font(.caption).foregroundStyle(accent) }
            Button("테스트 알림 보내기") { monitor.testNotification() }
            if let notice = monitor.lastNotice { Text("최근 이벤트\n\(notice)").font(.caption).foregroundStyle(muted) }
            Divider()
            Text("GPU 사용률은 GPU 전체 기준입니다. 진행률은 로그의 현재 단계 기준이며, 100%만으로 정상 완료를 판단하지 않습니다.").font(.caption).foregroundStyle(muted)
            Text("맥이 잠들거나 앱이 종료되면 조회가 멈춥니다. 다시 연결하면 현재 상태를 확인하지만, 그 사이 사라진 로그는 복구하지 못합니다.").font(.caption).foregroundStyle(muted)
            Spacer()
            HStack {
                Text("GPU Monitor 0.2.0").font(.caption).foregroundStyle(muted)
                Spacer()
                Button("앱 종료") { NSApplication.shared.terminate(nil) }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LogView: View {
    let server: ServerConfig
    let pane: Pane
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(pane.title).font(.headline).lineLimit(1)
                    Text("\(server.alias) · \(pane.location) · 최근 화면").font(.caption).foregroundStyle(muted)
                }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(pane.preview.isEmpty ? "표시할 로그가 없습니다." : pane.preview)
                    .font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12).background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            Text("읽기 전용 스냅샷 · 원격 터미널에 입력을 보내지 않습니다.").font(.caption).foregroundStyle(muted)
        }.padding(20).frame(width: 440, height: 430)
    }
}
