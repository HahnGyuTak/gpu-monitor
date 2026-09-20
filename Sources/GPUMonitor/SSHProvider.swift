import Foundation
import Darwin

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

struct MonitorError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Commands {
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil, timeout: Double = 25) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = arguments
                let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
                p.standardOutput = stdout
                p.standardError = stderr
                p.standardInput = stdin
                let finished = DispatchSemaphore(value: 0)
                p.terminationHandler = { _ in finished.signal() }
                do { try p.run() } catch { continuation.resume(throwing: error); return }
                let group = DispatchGroup()
                final class Buffer: @unchecked Sendable { var data = Data() }
                let outputBuffer = Buffer(), errorBuffer = Buffer()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    outputBuffer.data = stdout.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errorBuffer.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                DispatchQueue.global(qos: .utility).async {
                    if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
                    try? stdin.fileHandleForWriting.close()
                }
                let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
                if timedOut {
                    p.terminate()
                    if finished.wait(timeout: .now() + 1) == .timedOut {
                        kill(p.processIdentifier, SIGKILL)
                        _ = finished.wait(timeout: .now() + 2)
                    }
                }
                guard group.wait(timeout: .now() + 3) == .success else {
                    continuation.resume(throwing: MonitorError(message: "SSH 출력 수신 시간이 초과되었습니다.")); return
                }
                if timedOut { continuation.resume(throwing: MonitorError(message: "SSH 조회 시간 초과 · 연결 상태를 확인하세요.")); return }
                continuation.resume(returning: CommandResult(status: p.terminationStatus,
                    stdout: String(decoding: outputBuffer.data, as: UTF8.self), stderr: String(decoding: errorBuffer.data, as: UTF8.self)))
            }
        }
    }
}

// Additional data sources (e.g. W&B) can produce this same observation schema.
protocol ObservationProvider {
    func collect(_ config: ServerConfig) async throws -> (Snapshot, String?)
}

protocol TmuxSessionManaging {
    func deleteSession(_ session: TmuxSession, config: ServerConfig) async throws -> SessionDeletion
}

struct SSHProvider: ObservationProvider, TmuxSessionManaging {
    static func quoted(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func validAlias(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("-") && value.range(of: #"^[A-Za-z0-9_@.:-]+$"#, options: .regularExpression) != nil
    }
    static func inferContainer(_ command: String) throws -> String? {
        if command == "none" || command.isEmpty { return nil }
        let pattern = #"^(?:/usr/bin/)?docker\s+exec\s+(?:-it|-ti|-i|-t)\s+([A-Za-z0-9_.-]+)\s+(?:/bin/)?(?:bash|sh|zsh)(?:\s+-l)?$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
           let range = Range(match.range(at: 1), in: command) { return String(command[range]) }
        throw MonitorError(message: "이 서버의 RemoteCommand는 자동 처리할 수 없습니다. 서버 추가에서 컨테이너를 직접 지정하거나 ‘host’를 입력하세요.")
    }
    private func resolveContainer(_ config: ServerConfig) async throws -> String? {
        guard Self.validAlias(config.alias) else { throw MonitorError(message: "올바른 SSH 별칭을 입력하세요.") }
        let resolved: String?
        if let override = config.container { resolved = override.isEmpty ? nil : override }
        else {
            let result = try await Commands.run("/usr/bin/ssh", ["-G", config.alias], timeout: 5)
            guard result.status == 0 else { throw MonitorError(message: result.stderr) }
            let remote = result.stdout.components(separatedBy: .newlines).first(where: { $0.hasPrefix("remotecommand ") })?.dropFirst(14)
            resolved = try Self.inferContainer(remote.map(String.init) ?? "none")
        }
        return resolved
    }

    private func resource(_ name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "py") ?? Bundle.module.url(forResource: name, withExtension: "py") else {
            throw MonitorError(message: "\(name).py 리소스를 찾을 수 없습니다.")
        }
        return try String(contentsOf: url, encoding: .utf8) + "\n"
    }

    func collect(_ config: ServerConfig) async throws -> (Snapshot, String?) {
        let resolved = try await resolveContainer(config)
        let script = try resource("tmux_sessions") + resource("collector")
        let command: String
        if let resolved {
            guard let mappingURL = Bundle.main.url(forResource: "host_pid_map", withExtension: "py") ?? Bundle.module.url(forResource: "host_pid_map", withExtension: "py") else {
                throw MonitorError(message: "host_pid_map.py 리소스를 찾을 수 없습니다.")
            }
            let hostScript = try String(contentsOf: mappingURL, encoding: .utf8)
            command = "gpu_monitor_pid_map=$(python3 -c " + Self.quoted(hostScript) + " " + Self.quoted(resolved) + " 2>/dev/null) || gpu_monitor_pid_map='{}'; " +
                "docker exec -i -e GPU_MONITOR_CONTAINER=1 -e \"GPU_MONITOR_PID_MAP=$gpu_monitor_pid_map\" " + Self.quoted(resolved) + " python3 -"
        }
        else { command = "python3 -" }
        let data = try await execute(config, command: command, script: script)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version == 1 else { throw MonitorError(message: "지원하지 않는 수집 프로토콜입니다.") }
        return (snapshot, resolved)
    }

    func deleteSession(_ session: TmuxSession, config: ServerConfig) async throws -> SessionDeletion {
        let resolved = try await resolveContainer(config)
        let payload = try JSONEncoder().encode(session).base64EncodedString()
        let script = try resource("tmux_sessions") + "\nimport base64\nprint(json.dumps(delete_empty_session(json.loads(base64.b64decode('" + payload + "'))), ensure_ascii=False))\n"
        let command = resolved.map { "docker exec -i " + Self.quoted($0) + " python3 -" } ?? "python3 -"
        let data = try await execute(config, command: command, script: script)
        let response = try JSONDecoder().decode(SessionDeletion.self, from: data)
        guard response.version == 1 else { throw MonitorError(message: "지원하지 않는 삭제 응답입니다.") }
        return response
    }

    private func execute(_ config: ServerConfig, command: String, script: String) async throws -> Data {
        let arguments = ["-T", "-o", "RemoteCommand=none", "-o", "RequestTTY=no", "-o", "BatchMode=yes",
                         "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=8",
                         "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
                         "-o", "ClearAllForwardings=yes", config.alias, command]
        let result = try await Commands.run("/usr/bin/ssh", arguments, input: Data(script.utf8), timeout: 35)
        guard result.status == 0 else {
            let message = result.stderr.split(separator: "\n").filter { !$0.hasPrefix("**") }.suffix(4).joined(separator: "\n")
            throw MonitorError(message: message.isEmpty ? "SSH 종료 코드 \(result.status)" : message)
        }
        // Login banners can precede JSON; parse only the protocol object.
        guard let line = result.stdout.split(separator: "\n").last(where: { $0.hasPrefix("{\"version\":") }),
              let data = String(line).data(using: .utf8) else { throw MonitorError(message: "서버가 올바른 JSON을 반환하지 않았습니다. Python 3 및 RemoteCommand 설정을 확인하세요.") }
        return data
    }

}

enum SSHConfig {
    static func aliases() -> [String] {
        var visited = Set<String>(), hosts = Set<String>()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func read(_ path: String, depth: Int = 0) {
            guard depth < 8, visited.insert(path).inserted,
                  let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            for raw in content.components(separatedBy: .newlines) {
                let words = raw.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard let key = words.first?.lowercased(), !key.hasPrefix("#") else { continue }
                if key == "host" {
                    for host in words.dropFirst() where SSHProvider.validAlias(host) { hosts.insert(host) }
                } else if key == "include" {
                    for entry in words.dropFirst() {
                        var pattern = entry.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if pattern.hasPrefix("~/") { pattern = home + pattern.dropFirst() }
                        if !pattern.hasPrefix("/") { pattern = home + "/.ssh/" + pattern }
                        var matches = glob_t()
                        if Darwin.glob(pattern, 0, nil, &matches) == 0 {
                            for i in 0..<Int(matches.gl_pathc) {
                                if let p = matches.gl_pathv[i] { read(String(cString: p), depth: depth + 1) }
                            }
                        }
                        globfree(&matches)
                    }
                }
            }
        }
        read(home + "/.ssh/config")
        return hosts.sorted()
    }
}
