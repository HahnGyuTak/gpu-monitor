import SwiftUI

struct ServerCard: View {
    @Environment(\.monitorIconColor) private var iconColor
    @Environment(\.monitorAccent) private var accent
    @ObservedObject var monitor: Monitor
    let server: ServerConfig
    let filter: JobFilter
    @State private var expanded = true
    @State private var removing = false
    @State private var logPane: Pane?
    private var state: ServerViewState { monitor.states[server.id] ?? ServerViewState() }
    private var isMenuServer: Bool { monitor.menuServer?.id == server.id }
    private var busy: Bool { state.isLoading || monitor.deletingSessions[server.id] != nil }
    private var subtitle: String {
        if !server.enabled { return "서버 조회 중지" }
        if state.error != nil { return "연결 끊김" }
        if monitor.paused { return "자동 조회 일시 정지" }
        return state.resolvedContainer.map { "Docker · " + $0 } ?? (server.container == "" ? "SSH 호스트" : "SSH 서버")
    }
    private var jobs: [JobObservation] { state.visibleJobs(serverID: server.id, filter: filter, preferences: monitor.preferences) }
    private var sessions: [String] {
        var seen = Set<String>()
        return jobs.map { $0.pane.session }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded { content }
        }.padding(12).monitorSurface(.panel, radius: 16, selected: isMenuServer)
            .alert("서버를 목록에서 제거할까요?", isPresented: $removing) {
                Button("취소", role: .cancel) { }
                Button("목록에서 제거", role: .destructive) { monitor.remove(server.id) }
            } message: {
                Text("\(server.alias)의 메뉴바 고정과 알림 감시 설정도 해제됩니다. 원격 서버의 작업과 tmux 세션은 유지됩니다.")
            }
            .sheet(item: $logPane) { pane in
                LogView(monitor: monitor, server: server, initialPane: pane).monitorTheme(monitor.preferences.menuIconColor)
            }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(accent).frame(width: 10)
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        let gpuState = monitor.gpuState(for: server)
                        Image(nsImage: GPUPieIcon.image(for: gpuState, color: iconColor))
                            .resizable().frame(width: 20, height: 20).help(gpuState.toolTip)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.alias).font(.headline).foregroundStyle(Color.primary).lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text(subtitle).lineLimit(1).truncationMode(.middle)
                            if state.isLoading { ProgressView().controlSize(.mini).accessibilityHidden(true) }
                            else if state.updatedAt != nil {
                                TimelineView(.periodic(from: .now, by: 5)) { context in
                                    Text("· " + updatedText(state.updatedAt, now: context.date)).monospacedDigit()
                                }
                            }
                        }.font(.caption).foregroundStyle(state.error == nil ? muted : Color.orange)
                    }
                    Spacer(minLength: 0)
                }.frame(minHeight: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).help(server.alias + (expanded ? " · 접기" : " · 펼치기"))
                .accessibilityLabel(server.alias + (expanded ? " 접기" : " 펼치기"))
                .accessibilityValue(monitor.gpuState(for: server).toolTip)
            Button { monitor.selectMenuServer(server.id) } label: {
                AccentLabel(title: "메뉴바", symbol: isMenuServer ? "checkmark.circle.fill" : "circle")
            }.monitorAction().controlSize(.small).fixedSize()
                .help("이 서버의 GPU 요약을 메뉴바에 표시")
                .accessibilityLabel(server.alias + " 메뉴바에 표시")
                .accessibilityValue(isMenuServer ? "선택됨" : "선택 안 됨")
            Menu {
                Button {
                    monitor.setServerEnabled(server.id, enabled: !server.enabled)
                } label: { Label(server.enabled ? "서버 조회 중지" : "서버 조회 시작", systemImage: server.enabled ? "pause" : "play") }
                Divider()
                Button("목록에서 제거…", role: .destructive) { removing = true }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(accent).frame(width: 30, height: 30)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().monitorSurface(.chrome, radius: 8)
                .help(server.alias + " 서버 관리").accessibilityLabel(server.alias + " 서버 관리")
                .disabled(monitor.deletingSessions[server.id] != nil)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = state.error {
                VStack(alignment: .leading, spacing: 6) {
                    StatusMessage(symbol: "wifi.exclamationmark", title: state.snapshot == nil ? "서버에 연결하지 못했습니다" : "마지막으로 확인한 상태입니다", detail: error, warning: true)
                    if server.enabled {
                        Button { Task { await monitor.refresh(serverID: server.id) } } label: { AccentLabel(title: "다시 연결", symbol: "arrow.clockwise") }
                            .monitorAction().controlSize(.small).disabled(busy)
                    }
                }
            }
            if let snapshot = state.snapshot {
                GPUList(gpus: snapshot.gpus)
                    .padding(.horizontal, 8).padding(.vertical, 4).monitorSurface(.well, radius: 10)
                if snapshot.gpuPIDMappingLimited {
                    Label("GPU–pane 연결 일부 미확인", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(muted)
                        .help("컨테이너와 호스트의 PID가 달라 일부 작업의 GPU를 확인하지 못했습니다. GPU 사용률은 서버 전체 기준입니다.")
                }
                ForEach(snapshot.errors, id: \.self) { error in
                    StatusMessage(symbol: "exclamationmark.triangle", title: "일부 정보를 읽지 못했습니다", detail: error, warning: true)
                }
                tmuxContent(snapshot)
            } else if state.error == nil {
                StatusMessage(symbol: !server.enabled || monitor.paused ? "pause.circle" : "network",
                              title: !server.enabled || monitor.paused ? "아직 수집한 정보가 없습니다" : "첫 상태를 확인하고 있습니다",
                              detail: !server.enabled ? "서버 관리 메뉴에서 조회를 시작하세요." : (monitor.paused ? "상단의 재생 또는 새로고침 버튼을 누르세요." : "SSH로 GPU와 tmux 세션을 읽습니다."))
            }
        }
    }

    private func tmuxContent(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(title: "Tmux 세션", symbol: "terminal")
                Spacer()
                Text("\(snapshot.panes.count)개 pane · \(snapshot.panes.filter(\.active).count) 실행 중")
                    .font(.caption).monospacedDigit().foregroundStyle(muted)
                RowIconButton(symbol: "arrow.clockwise", label: server.alias + " tmux 목록 갱신") {
                    Task { await monitor.refresh(serverID: server.id) }
                }.disabled(!server.enabled || busy)
            }
            if let message = monitor.sessionMessages[server.id] {
                HStack(alignment: .top, spacing: 4) {
                    StatusMessage(symbol: "info.circle", title: message)
                    if monitor.deletingSessions[server.id] == nil {
                        RowIconButton(symbol: "xmark", label: "세션 메시지 닫기") { monitor.sessionMessages.removeValue(forKey: server.id) }
                    }
                }
            }
            if !snapshot.tmuxHealthy {
                StatusMessage(symbol: "exclamationmark.triangle", title: "tmux 목록 갱신이 지연되고 있습니다", detail: "아래 작업은 마지막으로 확인한 상태입니다.", warning: true)
            } else if sessions.isEmpty {
                Text(emptyTitle + (filter == .watched ? " · 작업의 감시를 켜면 표시됩니다." : ""))
                    .font(.callout).foregroundStyle(muted).padding(.vertical, 4)
            }
            ForEach(sessions, id: \.self) { session in
                SessionSection(monitor: monitor, server: server, session: session,
                               jobs: jobs.filter { $0.pane.session == session },
                               connected: state.error == nil && server.enabled && snapshot.tmuxHealthy,
                               showLogs: { logPane = $0 })
            }
        }.padding(.top, 2)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return "tmux 세션이 없습니다"
        case .running: return "실행 중인 작업이 없습니다"
        case .watched: return "감시 중인 작업이 없습니다"
        }
    }
}

struct GPUList: View {
    let gpus: [GPU]
    var body: some View {
        if gpus.isEmpty {
            StatusMessage(symbol: "cpu", title: "GPU 정보를 읽을 수 없습니다", detail: "조회 대상의 NVIDIA 드라이버와 nvidia-smi를 확인하세요.")
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("GPU").frame(maxWidth: .infinity, alignment: .leading)
                    Text("사용률 · 전체").frame(width: 104, alignment: .trailing)
                    Text("VRAM · GiB").frame(width: 96, alignment: .trailing)
                    Text("온도").frame(width: 40, alignment: .trailing)
                }.font(.caption).foregroundStyle(muted).padding(.vertical, 5)
                Divider()
                ForEach(gpus) { gpu in
                    GPURow(gpu: gpu)
                    if gpu.id != gpus.last?.id { Divider().opacity(0.4) }
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("GPU 상태")
        }
    }
}

struct GPURow: View {
    let gpu: GPU
    private var utilization: String { gpu.utilization.map { "\(Int($0))%" } ?? "—" }
    private var memoryText: String {
        "\(gpu.memoryUsed.map { String(format: "%.1f", $0 / 1024) } ?? "—") / \(gpu.memoryTotal.map { String(format: "%.0f", $0 / 1024) } ?? "—")"
    }
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(String(gpu.index)).monospacedDigit().foregroundStyle(muted).frame(width: 14, alignment: .trailing)
                Text(gpu.shortName).lineLimit(1).truncationMode(.middle).help(gpu.name)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                FractionBar(value: (gpu.utilization ?? 0) / 100).accessibilityHidden(true)
                Text(utilization).font(.body.weight(.medium)).monospacedDigit().lineLimit(1).frame(width: 44, alignment: .trailing)
            }.frame(width: 104)
            Text(memoryText).monospacedDigit().frame(width: 96, alignment: .trailing)
            Text(gpu.temperature.map { "\(Int($0))°C" } ?? "—").monospacedDigit().foregroundStyle(muted).frame(width: 40, alignment: .trailing)
        }.font(.callout).padding(.vertical, 7)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("GPU \(gpu.index), \(gpu.shortName), 사용률 \(utilization), VRAM \(memoryText) GiB, 온도 \(gpu.temperature.map { "\(Int($0))도" } ?? "미확인")")
    }
}

struct SessionSection: View {
    @Environment(\.monitorAccent) private var accent
    @ObservedObject var monitor: Monitor
    let server: ServerConfig
    let session: String
    let jobs: [JobObservation]
    let connected: Bool
    let showLogs: (Pane) -> Void
    @State private var expanded = true
    @State private var deletionCandidate: TmuxSession?
    private var info: TmuxSession? { monitor.states[server.id]?.snapshot?.sessions?.first { $0.name == session } }
    private var busy: Bool { monitor.deletingSessions[server.id] != nil || monitor.states[server.id]?.isLoading == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                        Text(session).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Text("\(jobs.count)개 pane").font(.caption).monospacedDigit().foregroundStyle(muted)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).help(session).accessibilityLabel(session + (expanded ? " 작업 접기" : " 작업 펼치기"))
                if info?.canDelete == true { Text("비어 있음").font(.caption).foregroundStyle(muted) }
                if monitor.deletingSessions[server.id] == info?.id && info != nil {
                    ProgressView().controlSize(.mini).frame(width: 30, height: 30)
                } else {
                    RowIconButton(symbol: "trash", label: session + " 빈 tmux 세션 삭제") { deletionCandidate = info }
                        .disabled(!connected || busy || info?.canDelete != true)
                        .help(info?.reason ?? "목록을 갱신하여 세션 상태를 확인하세요.")
                }
            }
            if expanded {
                ForEach(jobs, id: \.pane.id) { job in
                    JobRow(monitor: monitor, server: server, job: job, connected: connected, showLogs: showLogs)
                    if job.pane.id != jobs.last?.pane.id { Divider().opacity(0.4) }
                }
            }
        }.padding(8).monitorSurface(.well, radius: 10)
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

struct JobRow: View {
    @Environment(\.monitorAccent) private var accent
    @ObservedObject var monitor: Monitor
    let server: ServerConfig
    let job: JobObservation
    let connected: Bool
    let showLogs: (Pane) -> Void
    private var key: String { jobKey(server.id, job.pane.id) }
    private var isPinned: Bool { monitor.preferences.selected == key }
    private var isWatched: Bool { monitor.preferences.watched.contains(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: job.state == .running ? "play.circle.fill" : (job.state == .failed ? "exclamationmark.circle.fill" : "circle.dotted"))
                    .foregroundStyle(job.state == .failed ? Color.red : accent).font(.caption).accessibilityHidden(true)
                Text("Pane \(job.pane.window).\(job.pane.index)").font(.callout.weight(.semibold)).monospacedDigit()
                Text(job.state.label).font(.caption).foregroundStyle(muted).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Toggle("고정", isOn: Binding(get: { isPinned }, set: { _ in monitor.pin(server: server.id, pane: job.pane.id) }))
                        .help("메뉴바에 이 작업의 진행률 표시").accessibilityLabel(job.pane.location + " 메뉴바 고정")
                    Toggle("감시", isOn: Binding(get: { isWatched }, set: { _ in monitor.watch(server: server.id, pane: job.pane.id) }))
                        .help("새 오류와 종료 감시").accessibilityLabel(job.pane.location + " 알림 감시")
                    Button { showLogs(job.pane) } label: { AccentLabel(title: "로그", symbol: "text.alignleft") }
                        .monitorAction().accessibilityLabel(job.pane.location + " 로그 보기")
                }.toggleStyle(.checkbox).controlSize(.small).font(.callout).fixedSize()

            }
            if job.state == .running {
                if let progress = job.progress {
                    Text(gpuLabel).font(.caption).foregroundStyle(muted)
                    progressContent(progress)
                } else {
                    Text(gpuLabel + " · 진행률 미확인 · " + (job.pane.workers.first?.name ?? job.pane.command))
                        .font(.caption).foregroundStyle(muted).lineLimit(2)
                }
            }
            if isWatched && !monitor.preferences.notifications {
                Label("감시 중 · macOS 알림은 설정에서 켜 주세요", systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(muted)
            }
            if !connected { Text("마지막 확인 상태").font(.caption).foregroundStyle(muted) }
            if let error = job.pane.captureError { Text("화면 읽기 실패: \(error)").font(.caption).foregroundStyle(.orange) }
        }.padding(.horizontal, 8).padding(.vertical, 8)
            .background {
                if isPinned { MonitorGlassSurface(layer: .well, radius: 8, selected: true) }
            }
    }

    private var gpuLabel: String {
        let indices = job.pane.gpuIDs.compactMap { id in
            monitor.states[server.id]?.snapshot?.gpus.first { $0.id == id }.map { String($0.index) }
        }
        return indices.isEmpty ? "GPU 연결 미확인" : "GPU " + indices.joined(separator: ", ")
    }

    private func progressContent(_ progress: ProgressValue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.percent)%").font(.title3.weight(.semibold)).monospacedDigit()
                Text("\(progress.step) / \(progress.total)").font(.caption).monospacedDigit().foregroundStyle(muted)
                Spacer()
                Text("\(progress.etaSource == "estimate" ? "≈ " : "")ETA \(durationText(progress.etaSeconds))")
                    .font(.caption.weight(.medium)).monospacedDigit()
            }
            FractionBar(value: progress.fraction).accessibilityElement().accessibilityLabel("진행률").accessibilityValue("\(progress.percent)%")
            Text("현재 \(progress.scope == "epoch" ? "epoch" : "표시 단계") · \(progress.label)")
                .font(.caption).foregroundStyle(muted).lineLimit(1)
                .help("로그의 현재 진행 막대입니다. 전체 학습 진행률과 다를 수 있습니다.")
            TimelineView(.periodic(from: .now, by: 10)) { context in
                if job.lastProgressAt == nil {
                    Text("다음 진행 변화를 기다리고 있습니다").font(.caption).foregroundStyle(muted)
                } else if let last = job.lastProgressAt, context.date.timeIntervalSince(last) > 120 {
                    Label("2분 이상 진행률 변화 없음", systemImage: "clock").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}
