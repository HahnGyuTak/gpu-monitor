import AppKit
import Foundation
import UserNotifications

@MainActor final class Monitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var preferences: Preferences
    @Published var states: [String: ServerViewState] = [:]
    @Published var aliases: [String] = []
    @Published var notificationMessage: String?
    @Published var requestingNotifications = false
    @Published var paused = false
    @Published var lastNotice: String?
    var onChange: (() -> Void)?
    private var loop: Task<Void, Never>?
    private var polls: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    @Published var deletingSessions: [String: String] = [:]
    @Published var sessionMessages: [String: String] = [:]
    private var wakeObserver: NSObjectProtocol?
    private let provider: any ObservationProvider
    private let sessionManager: any TmuxSessionManaging
    private let defaultsKey = "GPUMonitor.preferences.v1"
    private let defaults: UserDefaults
    private var forceBaseline = false

    init(provider: any ObservationProvider = SSHProvider(), sessionManager: any TmuxSessionManaging = SSHProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.sessionManager = sessionManager
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey), let prefs = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = prefs }
        else { preferences = Preferences() }
        super.init()
        aliases = SSHConfig.aliases()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.forceBaseline = true; await self?.refresh() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if !self.paused { await self.refresh(manual: false) }
                try? await Task.sleep(nanoseconds: UInt64(self.preferences.interval * 1_000_000_000))
            }
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: defaultsKey) }
        onChange?()
    }

    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        onChange?()
        if !value { Task { await refresh() } }
    }

    func setServerEnabled(_ id: String, enabled: Bool) {
        guard let index = preferences.servers.firstIndex(where: { $0.id == id }) else { return }
        preferences.servers[index].enabled = enabled
        save()
        if enabled { Task { await refresh(serverID: id) } }
    }

    func refresh(serverID: String? = nil, manual: Bool = true) async {
        let servers = preferences.servers.filter { $0.enabled && (serverID == nil || $0.id == serverID) && deletingSessions[$0.id] == nil }
        var tasks: [Task<Void, Never>] = []
        for server in servers {
            let previous = polls[server.id]
            if let previous, !manual { tasks.append(previous.task); continue }
            let ticket = UUID()
            states[server.id, default: ServerViewState()].isLoading = true
            let task = Task { [weak self] in
                if let previous { await previous.task.value }
                guard let self else { return }
                await self.poll(server)
                if self.polls[server.id]?.id == ticket {
                    self.polls.removeValue(forKey: server.id)
                    if self.states[server.id] != nil { self.states[server.id]?.isLoading = false }
                }
                self.onChange?()
            }
            polls[server.id] = (ticket, task)
            tasks.append(task)
        }
        for task in tasks { await task.value }
        forceBaseline = false
        onChange?()
    }

    private func poll(_ server: ServerConfig) async {
        guard preferences.servers.contains(where: { $0.id == server.id && $0.enabled }) else { return }
        let id = server.id
        let result: Result<(Snapshot, String?), Error>
        do { result = .success(try await provider.collect(server)) }
        catch { result = .failure(error) }
        guard preferences.servers.contains(where: { $0.id == id && $0.enabled }) else { return }
        var state = states[id] ?? ServerViewState()
        switch result {
        case .failure(let error):
            state.error = error.localizedDescription
            // A failed transport is never a process-exit observation.
        case .success(let (snapshot, container)):
            let now = Date()
            let continuous = !forceBaseline && state.error == nil && state.updatedAt.map { now.timeIntervalSince($0) < max(60, preferences.interval * 4) } == true
            state.error = nil
            state.resolvedContainer = container
            if snapshot.tmuxHealthy {
                let present = Set(snapshot.panes.map(\.id))
                for pane in snapshot.panes {
                    let (job, notices) = JobTracker.update(previous: state.jobs[pane.id], pane: pane, at: now, continuous: continuous)
                    state.jobs[pane.id] = job
                    for notice in notices { send(notice, server: id, pane: pane.id) }
                }
                for paneID in Array(state.jobs.keys) where !present.contains(paneID) {
                    guard let old = state.jobs[paneID] else { continue }
                    let (job, notices) = JobTracker.missing(old)
                    state.jobs[paneID] = job
                    for notice in notices { send(notice, server: id, pane: paneID) }
                }
            }
            state.snapshot = snapshot
            state.updatedAt = now
        }
        states[id] = state
        onChange?()
    }

    func deleteSession(_ session: TmuxSession, server: ServerConfig) async {
        guard session.canDelete, deletingSessions[server.id] == nil, server.enabled else { return }
        deletingSessions[server.id] = session.id
        sessionMessages[server.id] = "삭제 전 세션과 실행 프로세스를 다시 확인하고 있습니다…"
        // Finish every queued observation before mutation, so stale results cannot restore it.
        if let previous = polls[server.id] { await previous.task.value }
        guard preferences.servers.contains(where: { $0.id == server.id && $0.enabled }) else {
            deletingSessions.removeValue(forKey: server.id)
            return
        }
        var target = server
        target.container = states[server.id]?.resolvedContainer ?? ""
        do {
            let result = try await sessionManager.deleteSession(session, config: target)
            sessionMessages[server.id] = result.message
            if result.deleted {
                let paneIDs = Set(session.paneIDs)
                for id in paneIDs { states[server.id]?.jobs.removeValue(forKey: id) }
                states[server.id]?.snapshot?.panes.removeAll { paneIDs.contains($0.id) }
                states[server.id]?.snapshot?.sessions?.removeAll { $0.id == session.id }
                let keys = Set(paneIDs.map { jobKey(server.id, $0) })
                preferences.watched.subtract(keys)
                if let selected = preferences.selected, keys.contains(selected) { preferences.selected = nil }
                save()
            }
        } catch {
            sessionMessages[server.id] = "삭제 결과를 확인하지 못했습니다: \(error.localizedDescription) 목록을 다시 조회합니다."
        }
        deletingSessions.removeValue(forKey: server.id)
        await refresh(serverID: server.id)
    }

    func add(alias: String, container: String) -> String? {
        let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SSHProvider.validAlias(alias) else { return "SSH 별칭 또는 user@host 형식으로 입력하세요." }
        let text = container.trimmingCharacters(in: .whitespacesAndNewlines)
        let override: String? = text.isEmpty ? nil : (text == "host" ? "" : text)
        guard !preferences.servers.contains(where: { $0.alias == alias && $0.container == override }) else { return "이미 등록된 서버입니다." }
        preferences.servers.append(ServerConfig(alias: alias, container: override))
        save()
        let id = preferences.servers.last?.id
        Task { await refresh(serverID: id) }
        return nil
    }

    func remove(_ id: String) {
        preferences.servers.removeAll { $0.id == id }
        preferences.watched = preferences.watched.filter { !$0.hasPrefix(id + "/") }
        if preferences.selected?.hasPrefix(id + "/") == true { preferences.selected = nil }
        if preferences.menuServerID == id { preferences.menuServerID = nil }
        states.removeValue(forKey: id)
        save()
    }

    func selectMenuServer(_ id: String) {
        guard preferences.servers.contains(where: { $0.id == id }) else { return }
        preferences.menuServerID = id
        preferences.selected = nil
        save()
    }

    func pin(server: String, pane: String) {
        guard preferences.servers.contains(where: { $0.id == server }) else { return }
        let key = jobKey(server, pane)
        preferences.selected = preferences.selected == key ? nil : key
        preferences.menuServerID = server
        save()
    }

    func watch(server: String, pane: String) {
        let key = jobKey(server, pane)
        if preferences.watched.contains(key) { preferences.watched.remove(key) }
        else { preferences.watched.insert(key) }
        save()
    }

    func setNotifications(_ enabled: Bool) {
        guard !requestingNotifications else { return }
        if !enabled { preferences.notifications = false; save(); return }
        requestingNotifications = true
        Task {
            defer { requestingNotifications = false }
            do {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .denied {
                    preferences.notifications = false
                    notificationMessage = "시스템 설정 → 알림 → GPU Monitor에서 ‘알림 허용’을 켠 다음 다시 활성화하세요."
                    save()
                    return
                }
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                preferences.notifications = allowed
                notificationMessage = allowed ? "벨을 켠 pane의 새 오류와 종료를 알립니다." : "시스템 설정 → 알림 → GPU Monitor에서 허용해 주세요."
                save()
            } catch {
                notificationMessage = "알림 권한을 요청하지 못했습니다. 시스템 알림 설정과 앱의 Apple 개발 서명을 확인하세요. (\(error.localizedDescription))"
            }
        }
    }

    func testNotification() {
        guard preferences.notifications else { notificationMessage = "먼저 알림을 켜 주세요."; return }
        deliver(title: "GPU Monitor", body: "알림이 연결되었습니다. 감시할 pane의 벨을 켜 주세요.", key: "test")
    }

    private func send(_ notice: JobNotice, server: String, pane: String) {
        guard preferences.watched.contains(jobKey(server, pane)) else { return }
        let name = preferences.servers.first(where: { $0.id == server })?.alias ?? server
        let job = states[server]?.jobs[pane]?.pane.session ?? pane
        lastNotice = "\(name) · \(job) · \(notice.title)"
        guard preferences.notifications else { return }
        deliver(title: "\(notice.title) · \(job)", body: "\(name)\n\(notice.body)", key: jobKey(server, pane))
    }

    private func deliver(title: String, body: String, key: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["jobKey": key]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error { self?.notificationMessage = error.localizedDescription }
                else if key == "test" { self?.notificationMessage = "테스트 알림을 macOS에 전달했습니다. 집중 모드·화면 공유 설정에 따라 배너가 숨겨질 수 있습니다." }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }

    var menuServer: ServerConfig? {
        if let selected = preferences.servers.first(where: { $0.id == preferences.menuServerID }) { return selected }
        // Preserve the menu target of preferences saved before server selection existed.
        let pinnedServer = preferences.servers.first { preferences.selected?.hasPrefix($0.id + "/") == true }
        return pinnedServer ?? preferences.servers.first(where: \.enabled) ?? preferences.servers.first
    }

    var menuGPUState: GPUPieState {
        guard let server = menuServer else {
            return GPUPieState(server: nil, slices: [], status: "서버를 추가하세요")
        }
        return gpuState(for: server)
    }

    func gpuState(for server: ServerConfig) -> GPUPieState {
        let state = states[server.id]
        let snapshot = state?.snapshot
        let status: String?
        if paused || !server.enabled { status = "일시 정지" }
        else if state?.error != nil { status = "연결 끊김 · 마지막 GPU 구성" }
        else if let updated = state?.updatedAt, Date().timeIntervalSince(updated) > max(45, preferences.interval * 3) { status = "갱신 지연" }
        else if snapshot == nil { status = "GPU 연결 중" }
        else { status = nil }
        return GPUPieState.make(server: server.alias, gpus: snapshot?.gpus ?? [], panes: snapshot?.panes ?? [], status: status)
    }

    var menuTitle: String {
        guard let server = menuServer else { return "GPU Monitor" }
        if let status = gpuState(for: server).status { return "\(server.alias) · \(status)" }
        let state = states[server.id]
        let selected = preferences.selected
        if let selected, selected.hasPrefix(server.id + "/"), let paneID = selected.split(separator: "/").last,
           let job = state?.jobs[String(paneID)] {
            let gpu = state?.snapshot?.gpus.first(where: { job.pane.gpuIDs.contains($0.id) })
            let prefix = gpu.map { "\($0.shortName) \(Int($0.utilization ?? 0))%" } ?? "\(server.alias)"
            if job.state != .running { return "\(String(job.pane.title.prefix(22))) · \(job.state.label)" }
            let progress = job.progress.map { "\($0.percent)%" } ?? "—"
            if preferences.compact { return "\(progress) · \(durationText(job.progress?.etaSeconds))" }
            return "\(prefix) · \(String(job.pane.title.prefix(20))) · \(progress) · ETA \(durationText(job.progress?.etaSeconds))"
        }
        let gpus = state?.snapshot?.gpus ?? []
        if let gpu = gpus.max(by: { ($0.utilization ?? -1) < ($1.utilization ?? -1) }) {
            return "\(server.alias) · \(gpu.shortName) \(gpu.utilization.map { String(Int($0)) } ?? "—")% · \(gpus.count) GPUs"
        }
        return "\(server.alias) · GPU 정보 없음"
    }
}
