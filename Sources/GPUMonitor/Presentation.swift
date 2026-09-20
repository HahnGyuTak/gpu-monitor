import Foundation

enum ServerFilter: CaseIterable {
    case all, running, querying
    var label: String {
        switch self {
        case .all: return "전체"
        case .running: return "실행"
        case .querying: return "조회"
        }
    }
    var summary: String {
        switch self {
        case .all: return "등록된 모든 서버 · 조회 중지 포함"
        case .running: return "SSH 조회 중이며 활성 GPU가 있는 서버"
        case .querying: return "SSH 조회가 켜진 모든 서버 · 연결 재시도 포함"
        }
    }
}

extension ServerViewState {
    func visibleJobs(serverID: String, preferences: Preferences) -> [JobObservation] {
        jobs.values.filter { job in
            let key = jobKey(serverID, job.pane.id)
            return job.state != .missing || preferences.watched.contains(key) || preferences.selected == key
        }.sorted {
            if ($0.state == .running) != ($1.state == .running) { return $0.state == .running }
            if $0.pane.session != $1.pane.session { return $0.pane.session.localizedStandardCompare($1.pane.session) == .orderedAscending }
            let left = (Int($0.pane.window) ?? 0, Int($0.pane.index) ?? 0)
            let right = (Int($1.pane.window) ?? 0, Int($1.pane.index) ?? 0)
            if left != right { return left < right }
            return $0.pane.id < $1.pane.id
        }
    }

    func currentPane(_ id: String) -> Pane? { snapshot?.panes.first { $0.id == id } }
}

func updatedText(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "아직 조회 안 됨" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 5 { return "방금 갱신" }
    if seconds < 60 { return "\(seconds)초 전" }
    if seconds < 3600 { return "\(seconds / 60)분 전" }
    if seconds < 86400 { return "\(seconds / 3600)시간 전" }
    return "\(seconds / 86400)일 전"
}
