import Foundation

struct JobNotice {
    var title: String
    var body: String
}

enum JobTracker {
    static func update(previous: JobObservation?, pane: Pane, at now: Date, continuous: Bool) -> (JobObservation, [JobNotice]) {
        var notices: [JobNotice] = []
        guard var old = previous else {
            return (JobObservation(pane: pane, state: pane.active ? .running : .idle,
                progress: pane.active ? pane.progress : nil,
                lastProgressAt: nil, seenEvents: Set(pane.events.map(\.fingerprint)),
                activeIdentity: pane.rootIdentity, lastSeen: now), [])
        }
        let wasActive = old.state == .running
        let replaced = old.pane.instance != pane.instance || (pane.active && old.activeIdentity != nil && old.activeIdentity != pane.rootIdentity)
        if replaced || (pane.active && old.state != .running) {
            let priorProgress = old.pane.progress
            if replaced && wasActive && continuous { notices.append(JobNotice(title: "실행 프로세스 변경", body: "기존 프로세스가 끝나고 새로운 프로세스가 감지되었습니다.")) }
            old = JobObservation(pane: pane, state: .running,
                progress: priorProgress?.step == pane.progress?.step && priorProgress?.total == pane.progress?.total ? nil : pane.progress,
                lastProgressAt: nil, seenEvents: Set(pane.events.map(\.fingerprint)),
                activeIdentity: pane.rootIdentity, lastSeen: now)
            old.awaitingFreshProgress = priorProgress?.step == pane.progress?.step && priorProgress?.total == pane.progress?.total
        }
        // Gaps and failed capture cannot justify a rate estimate or a new-log alert.
        if !continuous || pane.captureError != nil {
            old.seenEvents.formUnion(pane.events.map(\.fingerprint))
            old.lastProgressAt = nil
            old.rateSeconds = nil
        }
        let newEvents = pane.events.filter { !old.seenEvents.contains($0.fingerprint) }
        if let code = newEvents.last(where: { $0.kind == "exit" })?.exitCode { old.pendingExitCode = code }
        for event in newEvents where continuous && pane.captureError == nil {
            if event.kind == "oom" || event.kind == "error" {
                if old.alerted.insert(event.kind).inserted {
                    notices.append(JobNotice(title: event.kind == "oom" ? "OOM 로그 감지" : "오류 로그 감지", body: event.message))
                }
            }
        }
        old.seenEvents.formUnion(pane.events.map(\.fingerprint))
        if pane.active {
            old.state = .running
            old.idleSamples = 0
            old.activeIdentity = pane.rootIdentity
            let changedFromCapture = old.pane.progress?.step != pane.progress?.step || old.pane.progress?.total != pane.progress?.total || old.pane.progress?.label != pane.progress?.label
            if changedFromCapture { old.awaitingFreshProgress = false }
            if var progress = pane.progress, pane.captureError == nil, !old.awaitingFreshProgress {
                let previous = old.progress
                let changed = previous?.step != progress.step || previous?.total != progress.total || previous?.label != progress.label
                if changed {
                    if continuous, let previous, let last = old.lastProgressAt,
                       previous.total == progress.total, previous.label == progress.label, progress.step > previous.step {
                        let sample = now.timeIntervalSince(last) / Double(progress.step - previous.step)
                        old.rateSeconds = old.rateSeconds.map { 0.3 * sample + 0.7 * $0 } ?? sample
                    } else { old.rateSeconds = nil }
                    old.lastProgressAt = now
                }
                if progress.etaSeconds == nil, let rate = old.rateSeconds,
                   let last = old.lastProgressAt, now.timeIntervalSince(last) < 120 {
                    progress.etaSeconds = Double(progress.total - progress.step) * rate
                    progress.etaSource = "estimate"
                }
                // The old bar from a previous process is hidden until it changes.
                if old.progress != nil || changed { old.progress = progress }
            }
        } else {
            old.idleSamples += 1
            if let exitCode = old.pendingExitCode {
                old.state = exitCode == 0 ? .completed : .failed
            } else if pane.dead, let code = pane.exitCode, wasActive {
                old.state = code == 0 ? .completed : .failed
            } else if wasActive && old.idleSamples >= 2 { old.state = .stopped }
            if old.state != .running { old.progress = nil; old.rateSeconds = nil }
            if wasActive && old.state != .running && old.alerted.insert("end").inserted {
                notices.append(JobNotice(title: old.state.label,
                    body: old.state == .stopped ? "추적한 프로세스가 사라졌습니다. 성공 여부는 확인되지 않았습니다." : "실행 종료 코드가 확인되었습니다."))
            }
        }
        old.pane = pane
        old.lastSeen = now
        return (old, notices)
    }

    static func missing(_ old: JobObservation) -> (JobObservation, [JobNotice]) {
        var job = old
        job.idleSamples += 1
        if job.idleSamples >= 2 {
            job.progress = nil
            let wasRunning = job.state == .running
            job.state = .missing
            if wasRunning && job.alerted.insert("end").inserted {
                return (job, [JobNotice(title: "tmux pane 사라짐", body: "감시하던 pane이 사라졌습니다. 실행 결과는 확인되지 않았습니다.")])
            }
        }
        return (job, [])
    }
}
