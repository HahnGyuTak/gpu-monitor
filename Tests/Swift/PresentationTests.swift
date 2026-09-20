import Foundation

@main struct PresentationChecks {
    static func job(_ id: String, session: String = "exp_2", window: String = "0", state: JobState = .running) -> JobObservation {
        let pane = Pane(id: id, session: session, window: window, index: "0", pid: 10, command: "python", dead: false,
                        workers: [], instance: "10:1", gpuIDs: [], events: [], preview: "step 1")
        return JobObservation(pane: pane, state: state, lastSeen: Date())
    }
    static func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
    static func main() {
        let state = ServerViewState(jobs: ["%0": job("%0"), "%1": job("%1", state: .idle), "%2": job("%2", state: .missing), "%3": job("%3", state: .missing)])
        var preferences = Preferences(selected: "a/%2", watched: ["b/%0", "a/%1"])
        require(Set(state.visibleJobs(serverID: "a", filter: .all, preferences: preferences).map { $0.pane.id }) == ["%0", "%1", "%2"], "A missing pinned pane must stay accessible for logs; untracked missing panes must be hidden")
        require(state.visibleJobs(serverID: "a", filter: .running, preferences: preferences).map { $0.pane.id } == ["%0"], "Running filter must exclude idle and missing jobs")
        require(state.visibleJobs(serverID: "a", filter: .watched, preferences: preferences).map { $0.pane.id } == ["%1"], "Watches must be scoped to the server")
        preferences.watched.insert("a/%3")
        require(state.visibleJobs(serverID: "a", filter: .watched, preferences: preferences).contains { $0.pane.id == "%3" }, "A vanished watched pane must remain visible")
        print("PASS job filters preserve tracked missing panes and scope watches to each server")

        let sorted = ServerViewState(jobs: ["a": job("a", window: "10"), "b": job("b", window: "2"), "c": job("c", session: "exp_10"), "d": job("d", session: "exp_1", state: .idle)])
        require(sorted.visibleJobs(serverID: "a", filter: .all, preferences: Preferences()).map { $0.pane.id } == ["b", "a", "c", "d"], "Running jobs first, natural session order, numeric pane order")
        print("PASS stable natural ordering for sessions and pane windows")
        print("2 Presentation checks passed")
    }
}
