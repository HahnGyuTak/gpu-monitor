import Foundation

struct ServerConfig: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var alias: String
    // nil = infer a supported Docker RemoteCommand; empty = SSH host directly.
    var container: String? = nil
    var enabled = true
}

struct Preferences: Codable {
    var servers: [ServerConfig] = []
    var selected: String? = nil
    var menuServerID: String? = nil
    var watched: Set<String> = []
    var notifications = false
    var interval = 10.0
    var compact = false
}

struct GPU: Decodable, Identifiable {
    var index: Int
    var id: String
    var name: String
    var utilization: Double?
    var memoryUsed: Double?
    var memoryTotal: Double?
    var temperature: Double?
    var hasComputeProcess: Bool? = nil
    var shortName: String { name.replacingOccurrences(of: "NVIDIA ", with: "").replacingOccurrences(of: "GeForce ", with: "") }
    var memoryFraction: Double { min(1, max(0, (memoryUsed ?? 0) / max(1, memoryTotal ?? 1))) }
}

struct Worker: Decodable {
    var pid: Int
    var name: String
    var identity: String
}

struct ProgressValue: Decodable {
    var step: Int
    var total: Int
    var fraction: Double
    var etaSeconds: Double?
    var label: String
    var scope: String
    var source: String
    var etaSource: String?
    var percent: Int { Int((fraction * 100).rounded(.down)) }
}

struct LogEvent: Decodable {
    var kind: String
    var message: String
    var exitCode: Int?
    var runID: String?
    var fingerprint: String { kind + ":" + message }
}

struct Pane: Decodable, Identifiable {
    var id: String
    var session: String
    var window: String
    var index: String
    var pid: Int
    var command: String
    var dead: Bool
    var exitCode: Int?
    var workers: [Worker]
    var instance: String
    var gpuIDs: [String]
    var progress: ProgressValue?
    var events: [LogEvent]
    var captureError: String?
    var preview: String
    var active: Bool { !dead && !workers.isEmpty }
    var title: String { session }
    var location: String { "\(window).\(index) · \(id)" }
    var rootIdentity: String? { workers.first?.identity }
}

struct Snapshot: Decodable {
    var version: Int
    var timestamp: Double
    var gpus: [GPU]
    var panes: [Pane]
    var errors: [String]
    var tmuxAvailable: Bool
    var tmuxHealthy: Bool
    var gpuPIDMappingLimited: Bool
    var sessions: [TmuxSession]? = nil
}

struct TmuxSession: Codable, Identifiable {
    var id: String
    var name: String
    var paneIDs: [String]
    var canDelete: Bool
    var reason: String
    var token: String
}

struct SessionDeletion: Decodable {
    var version: Int
    var deleted: Bool
    var message: String
}

enum JobState: String {
    case running, idle, stopped, completed, failed, missing
    var label: String {
        switch self {
        case .running: return "실행 중"
        case .idle: return "대기"
        case .stopped: return "종료 · 원인 미확인"
        case .completed: return "정상 종료"
        case .failed: return "실패"
        case .missing: return "pane 사라짐"
        }
    }
}

struct JobObservation {
    var pane: Pane
    var state: JobState
    var progress: ProgressValue?
    var lastProgressAt: Date?
    var previousStep: Int?
    var previousTotal: Int?
    var rateSeconds: Double?
    var idleSamples = 0
    var seenEvents: Set<String> = []
    var alerted: Set<String> = []
    var generation = UUID().uuidString
    var activeIdentity: String?
    var lastSeen: Date
    var awaitingFreshProgress = false
    var pendingExitCode: Int?
}

struct ServerViewState {
    var snapshot: Snapshot?
    var updatedAt: Date?
    var error: String?
    var isLoading = false
    var resolvedContainer: String?
    var jobs: [String: JobObservation] = [:]
    var disconnected: Bool { error != nil }
}

func durationText(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
    let n = Int(seconds)
    if n >= 86400 { return "\(n / 86400)d \((n % 86400) / 3600)h" }
    if n >= 3600 { return "\(n / 3600)h \((n % 3600) / 60)m" }
    if n >= 60 { return "\(n / 60)m" }
    return "\(n)s"
}

func jobKey(_ server: String, _ pane: String) -> String { server + "/" + pane }
