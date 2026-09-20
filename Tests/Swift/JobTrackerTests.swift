import Foundation

final class JobTrackerTests {
    let now = Date(timeIntervalSince1970: 1000)
    func pane(active: Bool = true, step: Int = 63, events: [LogEvent] = [], identity: String = "42:100") -> Pane {
        Pane(id: "%3", session: "exp_042", window: "0", index: "0", pid: 1, command: "bash", dead: false, exitCode: nil,
             workers: active ? [Worker(pid: 42, name: "python", identity: identity)] : [], instance: "1:1", gpuIDs: [],
             progress: ProgressValue(step: step, total: 100, fraction: Double(step) / 100, etaSeconds: nil, label: "train", scope: "displayed", source: "tmux", etaSource: nil),
             events: events, captureError: nil, preview: "")
    }
    func testOldLogsOnConnectAreNotAlerts() {
        let oom = LogEvent(kind: "oom", message: "CUDA out of memory")
        let (job, alerts) = JobTracker.update(previous: nil, pane: pane(active: false, events: [oom]), at: now, continuous: false)
        expectTrue(alerts.isEmpty)
        expectEqual(job.state, .idle)
        expectNil(job.progress)
    }
    func testHundredPercentIsNotCompletion() {
        let (job, alerts) = JobTracker.update(previous: nil, pane: pane(step: 100), at: now, continuous: false)
        expectEqual(job.state, .running)
        expectTrue(alerts.isEmpty)
    }
    func testFreshOOMOnlyOnce() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(), at: now, continuous: false)
        let oom = LogEvent(kind: "oom", message: "CUDA out of memory")
        let (b, alerts) = JobTracker.update(previous: a, pane: pane(events: [oom]), at: now.addingTimeInterval(10), continuous: true)
        expectEqual(alerts.count, 1)
        expectEqual(b.state, .running)
        let (_, again) = JobTracker.update(previous: b, pane: pane(events: [oom]), at: now.addingTimeInterval(20), continuous: true)
        expectTrue(again.isEmpty)
    }
    func testReconnectDoesNotReplayErrors() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(), at: now, continuous: false)
        let (_, alerts) = JobTracker.update(previous: a, pane: pane(events: [LogEvent(kind: "oom", message: "CUDA out of memory")]), at: now.addingTimeInterval(600), continuous: false)
        expectTrue(alerts.isEmpty)
    }
    func testExitNeedsTwoObservationsAndDoesNotMeanSuccess() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(), at: now, continuous: false)
        let (b, first) = JobTracker.update(previous: a, pane: pane(active: false), at: now.addingTimeInterval(10), continuous: true)
        expectEqual(b.state, .running)
        expectTrue(first.isEmpty)
        let (c, second) = JobTracker.update(previous: b, pane: pane(active: false), at: now.addingTimeInterval(20), continuous: true)
        expectEqual(c.state, .stopped)
        expectEqual(second.count, 1)
        let (_, third) = JobTracker.update(previous: c, pane: pane(active: false), at: now.addingTimeInterval(30), continuous: true)
        expectTrue(third.isEmpty)
    }
    func testExplicitSuccessExit() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(), at: now, continuous: false)
        let event = LogEvent(kind: "exit", message: "GPU_MONITOR_EXIT run=a code=0", exitCode: 0, runID: "a")
        let (b, alerts) = JobTracker.update(previous: a, pane: pane(active: false, events: [event]), at: now.addingTimeInterval(10), continuous: true)
        expectEqual(b.state, .completed)
        expectEqual(alerts.count, 1)
    }
    func testExplicitFailureExit() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(), at: now, continuous: false)
        let event = LogEvent(kind: "exit", message: "GPU_MONITOR_EXIT run=a code=1", exitCode: 1, runID: "a")
        let (b, _) = JobTracker.update(previous: a, pane: pane(active: false, events: [event]), at: now.addingTimeInterval(10), continuous: true)
        expectEqual(b.state, .failed)
    }
    func testWrapperExitMarkerBeforeProcessDisappears() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(), at: now, continuous: false)
        let event = LogEvent(kind: "exit", message: "GPU_MONITOR_EXIT run=a code=0", exitCode: 0, runID: "a")
        let (b, _) = JobTracker.update(previous: a, pane: pane(events: [event]), at: now.addingTimeInterval(10), continuous: true)
        let (c, alerts) = JobTracker.update(previous: b, pane: pane(active: false, events: [event]), at: now.addingTimeInterval(20), continuous: true)
        expectEqual(c.state, .completed)
        expectEqual(alerts.count, 1)
    }
    func testRestartHidesUnchangedOldProgress() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(active: false), at: now, continuous: false)
        let (b, _) = JobTracker.update(previous: a, pane: pane(identity: "43:110"), at: now.addingTimeInterval(10), continuous: true)
        expectNil(b.progress)
        let (c, _) = JobTracker.update(previous: b, pane: pane(step: 64, identity: "43:110"), at: now.addingTimeInterval(20), continuous: true)
        expectEqual(c.progress?.step, 64)
    }
    func testETAAveragesOnlyAdvancingSteps() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(step: 10), at: now, continuous: false)
        let (b, _) = JobTracker.update(previous: a, pane: pane(step: 20), at: now.addingTimeInterval(10), continuous: true)
        expectNil(b.progress?.etaSeconds)
        let (c, _) = JobTracker.update(previous: b, pane: pane(step: 30), at: now.addingTimeInterval(20), continuous: true)
        expectEqual(c.progress?.etaSeconds, 70)
        let (d, _) = JobTracker.update(previous: c, pane: pane(step: 1), at: now.addingTimeInterval(30), continuous: true)
        expectNil(d.progress?.etaSeconds)
    }
    func testMissingIsNotSuccess() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(), at: now, continuous: false)
        let (b, first) = JobTracker.missing(a)
        expectTrue(first.isEmpty)
        let (c, second) = JobTracker.missing(b)
        expectEqual(c.state, .missing)
        expectEqual(second.count, 1)
    }
    func testMissingIdlePaneIsRemovedWithoutAlert() {
        let (a, _) = JobTracker.update(previous: nil, pane: pane(active: false), at: now, continuous: false)
        let (b, _) = JobTracker.missing(a)
        let (c, alerts) = JobTracker.missing(b)
        expectEqual(c.state, .missing)
        expectTrue(alerts.isEmpty)
    }
    func testDockerConfigAndShellQuoting() throws {
        expectEqual(try SSHProvider.inferContainer("docker exec -it training-container /bin/bash"), "training-container")
        expectNil(try SSHProvider.inferContainer("none"))
        expectThrows(try SSHProvider.inferContainer("some-arbitrary-script"))
        expectFalse(SSHProvider.validAlias("-oProxyCommand=bad"))
        expectFalse(SSHProvider.validAlias("host; touch /tmp/no"))
        expectEqual(SSHProvider.quoted("a'b"), "'a'\\''b'")
    }
}

// Standalone checks work with Command Line Tools; XCTest requires full Xcode.
func expectTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) { precondition(value(), "Expected true", file: file, line: line) }
func expectFalse(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value(), "Expected false", file: file, line: line) }
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Values differ: \(a) != \(b)", file: file, line: line) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { _ = try expression() } catch { return }; preconditionFailure("Expected an error", file: file, line: line) }
extension Bundle { static var module: Bundle { .main } }

@main enum RunChecks {
    static func main() throws {
        let tests = JobTrackerTests()
        let cases: [(String, () throws -> Void)] = [
            ("testOldLogsOnConnectAreNotAlerts", tests.testOldLogsOnConnectAreNotAlerts),
            ("testHundredPercentIsNotCompletion", tests.testHundredPercentIsNotCompletion),
            ("testFreshOOMOnlyOnce", tests.testFreshOOMOnlyOnce),
            ("testReconnectDoesNotReplayErrors", tests.testReconnectDoesNotReplayErrors),
            ("testExitNeedsTwoObservationsAndDoesNotMeanSuccess", tests.testExitNeedsTwoObservationsAndDoesNotMeanSuccess),
            ("testExplicitSuccessExit", tests.testExplicitSuccessExit),
            ("testExplicitFailureExit", tests.testExplicitFailureExit),
            ("testWrapperExitMarkerBeforeProcessDisappears", tests.testWrapperExitMarkerBeforeProcessDisappears),
            ("testRestartHidesUnchangedOldProgress", tests.testRestartHidesUnchangedOldProgress),
            ("testETAAveragesOnlyAdvancingSteps", tests.testETAAveragesOnlyAdvancingSteps),
            ("testMissingIsNotSuccess", tests.testMissingIsNotSuccess),
            ("testMissingIdlePaneIsRemovedWithoutAlert", tests.testMissingIdlePaneIsRemovedWithoutAlert),
            ("testDockerConfigAndShellQuoting", tests.testDockerConfigAndShellQuoting)
        ]
        for (name, test) in cases { try test(); print("PASS \(name)") }
        print("\(cases.count) Swift checks passed")
    }
}
