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
        VStack(alignment: .leading, spacing: 14) {
            header
            if expanded { content }
        }.padding(16).monitorCard(radius: 22)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isMenuServer ? accent.opacity(0.32) : Color.clear, lineWidth: 1))
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
                            .resizable().frame(width: 24, height: 24).help(gpuState.toolTip)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.alias).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1)
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(state.error == nil ? muted : Color.orange).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.frame(minHeight: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).help(server.alias + (expanded ? " · 접기" : " · 펼치기"))
                .accessibilityLabel(server.alias + (expanded ? " 접기" : " 펼치기"))
                .accessibilityValue(monitor.gpuState(for: server).toolTip)
            Button { monitor.selectMenuServer(server.id) } label: {
                Label("메뉴바", systemImage: isMenuServer ? "checkmark.circle.fill" : "circle")
            }.buttonStyle(MonitorButtonStyle(selected: isMenuServer, embedded: true)).fixedSize()
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
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(server.alias + " 서버 관리").accessibilityLabel(server.alias + " 서버 관리")
                .disabled(monitor.deletingSessions[server.id] != nil)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                if state.isLoading { ProgressView().controlSize(.mini); Text("갱신 중") }
                else {
                    Image(systemName: !server.enabled || monitor.paused ? "pause.circle" : (state.error == nil ? "checkmark.circle" : "wifi.exclamationmark"))
                        .foregroundStyle(state.error == nil ? accent : Color.orange).accessibilityHidden(true)
                    Text(!server.enabled ? "서버 조회 중지" : (monitor.paused ? "자동 조회 일시 정지" : (state.error == nil ? "연결 상태" : "연결 끊김")))
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text(updatedText(state.updatedAt, now: context.date)).monospacedDigit()
                }
            }.font(.system(size: 11)).foregroundStyle(muted)
            if let error = state.error {
                VStack(alignment: .leading, spacing: 6) {
                    StatusMessage(symbol: "wifi.exclamationmark", title: state.snapshot == nil ? "서버에 연결하지 못했습니다" : "마지막으로 확인한 상태입니다", detail: error, warning: true)
                    if server.enabled {
                        Button { Task { await monitor.refresh(serverID: server.id) } } label: { Label("다시 연결", systemImage: "arrow.clockwise") }
                            .buttonStyle(MonitorButtonStyle(embedded: true)).disabled(busy)
                    }
                }
            }
            if let snapshot = state.snapshot {
                GPUGrid(gpus: snapshot.gpus)
                if snapshot.gpuPIDMappingLimited {
                    Label("GPU–pane 연결 일부 미확인", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(muted)
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
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(muted)
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
                StatusMessage(symbol: filter == .watched ? "bell" : "terminal", title: emptyTitle, detail: emptyDetail)
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
    private var emptyDetail: String {
        filter == .watched ? "전체 탭에서 작업의 벨을 켜면 이곳에 표시됩니다." : "원격 서버에서 tmux 작업을 시작하면 자동으로 표시됩니다."
    }
}

struct GPUGrid: View {
    let gpus: [GPU]
    var body: some View {
        if gpus.isEmpty {
            StatusMessage(symbol: "cpu", title: "GPU 정보를 읽을 수 없습니다", detail: "조회 대상의 NVIDIA 드라이버와 nvidia-smi를 확인하세요.")
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(gpus) { gpu in GPUCard(gpu: gpu) }
            }
        }
    }
}

struct GPUCard: View {
    @Environment(\.monitorAccent) private var accent
    let gpu: GPU
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text("GPU \(gpu.index)").foregroundStyle(muted) } icon: { Image(systemName: "cpu").foregroundStyle(accent) }
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(gpu.utilization.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 24, weight: .semibold)).monospacedDigit()
            }
            Text(gpu.shortName).font(.system(size: 11, weight: .medium)).lineLimit(1).help(gpu.name)
            FractionBar(value: (gpu.utilization ?? 0) / 100).accessibilityHidden(true)
            HStack(spacing: 2) {
                Text("VRAM \(memoryText)")
                Spacer(minLength: 0)
                Text(gpu.temperature.map { "\(Int($0))°C" } ?? "—")
            }.font(.system(size: 11)).monospacedDigit().foregroundStyle(muted)
        }.padding(12).background(inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("GPU \(gpu.index), \(gpu.shortName), 사용률 \(gpu.utilization.map { "\(Int($0))%" } ?? "미확인"), VRAM \(memoryText), 온도 \(gpu.temperature.map { "\(Int($0))도" } ?? "미확인")")
    }

    private var memoryText: String {
        "\(gpu.memoryUsed.map { String(format: "%.1f", $0 / 1024) } ?? "—") / \(gpu.memoryTotal.map { String(format: "%.0f", $0 / 1024) } ?? "—") GiB"
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
                        Text(session).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("\(jobs.count)개 pane").font(.system(size: 11)).monospacedDigit().foregroundStyle(muted)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).help(session).accessibilityLabel(session + (expanded ? " 작업 접기" : " 작업 펼치기"))
                if info?.canDelete == true { Text("비어 있음").font(.system(size: 11)).foregroundStyle(muted) }
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
                    .foregroundStyle(job.state == .failed ? Color.red : accent).font(.system(size: 11)).accessibilityHidden(true)
                Text("Pane \(job.pane.window).\(job.pane.index)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Text(job.state.label).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    RowIconButton(symbol: isPinned ? "pin.fill" : "pin", label: job.pane.location + (isPinned ? " 메뉴바 고정 해제" : " 메뉴바에 고정"), selected: isPinned) {
                        monitor.pin(server: server.id, pane: job.pane.id)
                    }.accessibilityValue(isPinned ? "고정됨" : "고정 안 됨")
                    RowIconButton(symbol: isWatched ? "bell.fill" : "bell", label: job.pane.location + (isWatched ? " 알림 감시 해제" : " 알림 감시"), selected: isWatched) {
                        monitor.watch(server: server.id, pane: job.pane.id)
                    }.accessibilityValue(isWatched ? "감시 중" : "감시 안 함")
                    RowIconButton(symbol: "text.alignleft", label: job.pane.location + " 로그 보기") { showLogs(job.pane) }
                }
            }
            if job.state == .running {
                Text(gpuLabel).font(.system(size: 11)).foregroundStyle(muted)
                if let progress = job.progress { progressContent(progress) }
                else { Text("진행률 기다리는 중 · \(job.pane.workers.first?.name ?? job.pane.command)").font(.system(size: 11)).foregroundStyle(muted) }
            }
            if isWatched && !monitor.preferences.notifications {
                Label("감시 중 · macOS 알림은 설정에서 켜 주세요", systemImage: "bell.slash")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            if !connected { Text("마지막 확인 상태").font(.system(size: 11)).foregroundStyle(muted) }
            if let error = job.pane.captureError { Text("화면 읽기 실패: \(error)").font(.system(size: 11)).foregroundStyle(.orange) }
        }.padding(12).background(isPinned ? accent.opacity(0.08) : inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isPinned ? accent.opacity(0.2) : Color.clear))
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
                Text("\(progress.percent)%").font(.system(size: 16, weight: .semibold)).monospacedDigit()
                Text("\(progress.step) / \(progress.total)").font(.system(size: 11)).monospacedDigit().foregroundStyle(muted)
                Spacer()
                Text("\(progress.etaSource == "estimate" ? "≈ " : "")ETA \(durationText(progress.etaSeconds))")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            FractionBar(value: progress.fraction).accessibilityElement().accessibilityLabel("진행률").accessibilityValue("\(progress.percent)%")
            Text("현재 \(progress.scope == "epoch" ? "epoch" : "표시 단계") · \(progress.label)")
                .font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                .help("로그의 현재 진행 막대입니다. 전체 학습 진행률과 다를 수 있습니다.")
            TimelineView(.periodic(from: .now, by: 10)) { context in
                if job.lastProgressAt == nil {
                    Text("다음 진행 변화를 기다리고 있습니다").font(.system(size: 11)).foregroundStyle(muted)
                } else if let last = job.lastProgressAt, context.date.timeIntervalSince(last) > 120 {
                    Label("2분 이상 진행률 변화 없음", systemImage: "clock").font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
        }
    }
}
