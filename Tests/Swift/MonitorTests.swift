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
        let monitor = Monitor(provider: provider, sessionManager: deletion)
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
        print("3 Monitor integration checks passed")
    }
}
