import AppKit
import Foundation

extension Bundle { static var module: Bundle { .main } }

private let emptySnapshot = Snapshot(version: 1, timestamp: 0, gpus: [], panes: [], errors: [], tmuxAvailable: false, tmuxHealthy: true, gpuPIDMappingLimited: false)

private actor ControlledProvider: ObservationProvider {
    var calls: [String] = []
    var waiting: [String: [CheckedContinuation<(Snapshot, String?), Error>]] = [:]
    func collect(_ config: ServerConfig) async throws -> (Snapshot, String?) {
        calls.append(config.id)
        return try await withCheckedThrowingContinuation { waiting[config.id, default: []].append($0) }
    }
    func count() -> Int { calls.count }
    func finish(_ id: String, snapshot: Snapshot = emptySnapshot) {
        guard waiting[id]?.isEmpty == false else { fatalError("No pending observation") }
        waiting[id]!.removeFirst().resume(returning: (snapshot, "test-container"))
    }
}

private actor ControlledDeletion: TmuxSessionManaging {
    var calls = 0
    var target: ServerConfig?
    var waiting: CheckedContinuation<SessionDeletion, Error>?
    func deleteSession(_ session: TmuxSession, config: ServerConfig) async throws -> SessionDeletion {
        calls += 1
        target = config
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func count() -> Int { calls }
    func container() -> String? { target?.container }
    func finish() { waiting?.resume(returning: SessionDeletion(version: 1, deleted: true, message: "deleted")); waiting = nil }
}

@main struct MonitorChecks {
    @MainActor static func waitFor(_ predicate: () async -> Bool) async {
        for _ in 0..<2000 {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Timed out waiting for test state")
    }

    @MainActor static func require(_ value: Bool, _ description: String) {
        if !value { fatalError(description) }
    }

    @MainActor static func main() async {
        let a = ServerConfig(id: "a", alias: "a"), b = ServerConfig(id: "b", alias: "b")
        let provider = ControlledProvider(), deletion = ControlledDeletion()
        let suite = "GPU-Monitor-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = Monitor(provider: provider, sessionManager: deletion, defaults: defaults)
        monitor.preferences = Preferences(servers: [a, b])

        let first = Task { await monitor.refresh() }
        await waitFor { await provider.count() == 2 }
        require(monitor.states["a"]?.isLoading == true && monitor.states["b"]?.isLoading == true, "Servers must load concurrently")
        await provider.finish("a"); await provider.finish("b"); await first.value
        print("PASS concurrent server refresh")

        let targeted = Task { await monitor.refresh(serverID: "a") }
        await waitFor { await provider.count() == 3 }
        require(monitor.states["b"]?.isLoading == false, "Targeted refresh must not reload another server")
        let queued = Task { await monitor.refresh(serverID: "a") }
        await Task.yield()
        await provider.finish("a")
        await waitFor { await provider.count() == 4 }
        require(monitor.states["a"]?.isLoading == true, "Loading must remain true for queued manual refresh")
        await provider.finish("a"); await targeted.value; await queued.value
        print("PASS targeted refresh and queued manual refresh")

        let session = TmuxSession(id: "$0", name: "empty", paneIDs: ["%0"], canDelete: true, reason: "idle", token: String(repeating: "a", count: 64))
        monitor.preferences.selected = "a/%0"
        monitor.preferences.watched = ["a/%0", "b/%9"]
        let observation = Task { await monitor.refresh(serverID: "a") }
        await waitFor { await provider.count() == 5 }
        let removal = Task { await monitor.deleteSession(session, server: a) }
        await waitFor { monitor.deletingSessions["a"] != nil }
        require(await deletion.count() == 0, "Delete must await the in-flight observation")
        await monitor.refresh(serverID: "a")
        require(await provider.count() == 5, "Do not collect during a pending deletion")
        await provider.finish("a"); await observation.value
        await waitFor { await deletion.count() == 1 }
        require(await deletion.container() == "test-container", "Delete must target the observed container")
        await deletion.finish()
        await waitFor { await provider.count() == 6 }
        require(monitor.preferences.selected == nil && monitor.preferences.watched == ["b/%9"], "Deletion must clear only the removed pane's pin and watch")
        await provider.finish("a"); await removal.value
        require(monitor.states["a"]?.isLoading == false && monitor.deletingSessions.isEmpty, "Mutation must end with refreshed state")
        print("PASS deletion waits for observations, preserves target, cleans preferences, and refreshes")

        monitor.setServerEnabled("b", enabled: false)
        monitor.setServerEnabled("a", enabled: false)
        await monitor.refresh()
        require(await provider.count() == 6, "Disabled servers must not be queried")
        monitor.setServerEnabled("a", enabled: true)
        await waitFor { await provider.count() == 7 }
        require(monitor.states["b"]?.isLoading == false, "Enabling one server must not query another")
        await provider.finish("a")
        await waitFor { monitor.states["a"]?.isLoading == false }
        monitor.setPaused(true)
        require(monitor.paused, "Pause state must be published immediately")
        monitor.setPaused(false)
        await waitFor { await provider.count() == 8 }
        await provider.finish("a")
        await waitFor { monitor.states["a"]?.isLoading == false }
        require(!monitor.paused, "Resuming must immediately refresh enabled servers")
        print("PASS per-server enable and immediate refresh on resume")

        let now = Date(timeIntervalSince1970: 10_000)
        func gpu(utilization: Double? = 0, compute: Bool = false, memory: Double = 0) -> GPU {
            GPU(index: 0, id: "gpu-0", name: "Test GPU", utilization: utilization,
                memoryUsed: memory, memoryTotal: 40960, temperature: nil, hasComputeProcess: compute)
        }
        func state(_ gpu: GPU, panes: [Pane] = [], age: TimeInterval = 0, error: String? = nil) -> ServerViewState {
            var snapshot = emptySnapshot
            snapshot.gpus = [gpu]
            snapshot.panes = panes
            return ServerViewState(snapshot: snapshot, updatedAt: now.addingTimeInterval(-age), error: error)
        }
        let stopped = ServerConfig(id: "stopped", alias: "stopped", enabled: false)
        let active = ServerConfig(id: "active", alias: "active")
        let idle = ServerConfig(id: "idle", alias: "idle")
        monitor.preferences = Preferences(servers: [stopped, active, idle])
        monitor.states = [stopped.id: state(gpu(utilization: 99)), active.id: state(gpu(utilization: 72)), idle.id: state(gpu())]
        require(monitor.visibleServers(matching: .all, at: now).map(\.id) == ["stopped", "active", "idle"], "All must preserve registered server order, including stopped servers")
        require(monitor.visibleServers(matching: .querying, at: now).map(\.id) == ["active", "idle"], "Querying means polling enabled, including the gap between SSH requests")
        require(monitor.visibleServers(matching: .running, at: now).map(\.id) == ["active"], "Running must filter server cards and exclude stopped servers with cached active GPUs")
        print("PASS server filters distinguish all, querying and GPU-active servers")

        let worker = Worker(pid: 12, name: "python", identity: "12:1")
        let mapped = Pane(id: "%0", session: "train", window: "0", index: "0", pid: 11, command: "python", dead: false,
                          workers: [worker], instance: "11:1", gpuIDs: ["gpu-0"], events: [], preview: "training")
        var cpuOnly = mapped
        cpuOnly.gpuIDs = []
        let signals: [(String, GPU, [Pane])] = [
            ("utilization", gpu(utilization: 1), []), ("compute", gpu(utilization: nil, compute: true), []),
            ("mapped", gpu(), [mapped]), ("cpu-only", gpu(), [cpuOnly]),
            ("memory-only", gpu(memory: 32768), []), ("unknown", gpu(utilization: nil), [])
        ]
        monitor.preferences.servers = signals.map { ServerConfig(id: $0.0, alias: $0.0) }
        monitor.states = Dictionary(uniqueKeysWithValues: signals.map { ($0.0, state($0.1, panes: $0.2)) })
        require(monitor.visibleServers(matching: .running, at: now).map(\.id) == ["utilization", "compute", "mapped"], "Use the icon's GPU activity evidence; CPU tmux jobs and VRAM allocation alone must not qualify")
        print("PASS running filter uses GPU evidence rather than tmux activity or allocated memory")

        monitor.preferences.servers = ["fresh", "stale", "failed", "connecting"].map { ServerConfig(id: $0, alias: $0) }
        monitor.states = ["fresh": state(gpu(compute: true), age: 45), "stale": state(gpu(compute: true), age: 46),
                          "failed": state(gpu(compute: true), error: "SSH disconnected"), "connecting": ServerViewState(isLoading: true)]
        require(monitor.visibleServers(matching: .running, at: now).map(\.id) == ["fresh"], "Unknown, failed and stale observations must not appear as GPU execution")
        require(monitor.visibleServers(matching: .querying, at: now).count == 4, "Pending connections and retries must remain available in Querying")
        require(monitor.visibleServers(matching: .running, at: now.addingTimeInterval(1)).isEmpty, "Running results must expire without receiving another observation")
        monitor.preferences.interval = 60
        require(monitor.visibleServers(matching: .running, at: now).map(\.id) == ["fresh", "stale"], "Freshness must respect the configured polling interval")
        print("PASS server execution filtering handles stale data, SSH failure and initial connection")

        monitor.paused = true
        require(monitor.visibleServers(matching: .all, at: now).count == 4, "Pause must not remove registered servers from All")
        require(monitor.visibleServers(matching: .running, at: now).isEmpty && monitor.visibleServers(matching: .querying, at: now).isEmpty, "Paused monitoring must not claim servers are currently being queried, even with an in-flight request")
        print("PASS paused polling is separate from per-server query settings")
        print("8 Monitor integration checks passed")
    }
}
