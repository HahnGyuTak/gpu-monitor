import AppKit
import SwiftUI

struct SheetHeader: View {
    @Environment(\.monitorAccent) private var accent
    let title: String
    let subtitle: String
    let symbol: String
    let close: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle).help(title)
                Text(subtitle).font(.caption).foregroundStyle(muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            GlassIconButton(symbol: "xmark", label: "닫기 · Esc", action: close).keyboardShortcut(.cancelAction)
        }
    }
}

struct AddServerView: View {
    @ObservedObject var monitor: Monitor
    let close: () -> Void
    @State private var alias = ""
    @State private var container = ""
    @State private var target = 0
    @State private var error: String?
    @FocusState private var focused: Field?
    private enum Field { case alias, container }
    private var ready: Bool {
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (target != 2 || !container.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "SSH 서버 추가", subtitle: "SSH 별칭 또는 user@host", symbol: "server.rack") { close() }
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SSH 별칭 또는 주소").font(.callout.weight(.medium))
                    HStack(spacing: 8) {
                        TextField("예: training-server 또는 user@host", text: $alias)
                            .focused($focused, equals: .alias).accessibilityLabel("SSH 별칭 또는 주소")
                            .monitorTextInput(focused: focused == .alias)
                        Menu {
                            ForEach(monitor.aliases, id: \.self) { name in
                                Button(name) { alias = name; error = nil; focused = .alias }
                            }
                        } label: {
                            Text("SSH 설정")
                        }.menuStyle(.button).monitorAction().controlSize(.large).fixedSize()
                            .disabled(monitor.aliases.isEmpty).help("SSH 설정에서 선택").accessibilityLabel("SSH 설정에서 별칭 선택")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("조회 대상").font(.callout.weight(.medium))
                    MonitorSegmentedPicker(label: "조회 대상", options: [(0, "자동 감지"), (1, "SSH 호스트"), (2, "Docker")], selection: $target)
                    if target == 2 {
                        TextField("컨테이너 이름", text: $container)
                            .focused($focused, equals: .container).accessibilityLabel("Docker 컨테이너 이름")
                            .monitorTextInput(focused: focused == .container)
                    }
                    Text(target == 0 ? "SSH 설정의 Docker RemoteCommand를 자동 인식합니다." : (target == 1 ? "컨테이너를 거치지 않고 SSH 호스트를 조회합니다." : "해당 컨테이너 내부의 GPU와 tmux를 조회합니다."))
                        .font(.caption).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(12).monitorSurface(.panel)
            if let error { StatusMessage(symbol: "exclamationmark.triangle", title: error, warning: true) }
            Text("SSH 키 인증을 사용합니다. 터미널에서 한 번 연결해 호스트 키를 확인한 서버를 추가하세요.")
                .font(.caption).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            MonitorGlassGroup {
                HStack {
                    Button("취소") { close() }.monitorAction()
                    Spacer()
                    Button { add() } label: { Label("서버 추가", systemImage: "plus") }
                        .monitorAction(primary: true).keyboardShortcut(.defaultAction).disabled(!ready)
                }
            }
        }.padding(20).frame(width: 470).background { DashboardBackdrop() }.font(.body)
            .onAppear { focused = .alias }
            .onChange(of: alias) { _ in error = nil }
            .onChange(of: container) { _ in error = nil }
            .onChange(of: target) { _ in error = nil }
            .task(id: target) {
                if target == 2 {
                    await Task.yield()
                    focused = .container
                }
            }
    }

    private func add() {
        guard ready else { return }
        if target == 2 && container.trimmingCharacters(in: .whitespacesAndNewlines) == "host" {
            error = "host는 SSH 호스트 조회용 예약어입니다. 다른 컨테이너 이름을 입력하세요."
            return
        }
        error = monitor.add(alias: alias, container: target == 1 ? "host" : (target == 2 ? container : ""))
        if error == nil { close() }
        else { focused = .alias }
    }
}

struct LogView: View {
    @ObservedObject var monitor: Monitor
    let server: ServerConfig
    let initialPane: Pane
    @Environment(\.dismiss) private var dismiss
    @State private var wrap = true
    @State private var copied = false
    private var state: ServerViewState { monitor.states[server.id] ?? ServerViewState() }
    private var pane: Pane { state.currentPane(initialPane.id) ?? state.jobs[initialPane.id]?.pane ?? initialPane }
    private var serverEnabled: Bool { monitor.preferences.servers.first { $0.id == server.id }?.enabled == true }
    private var busy: Bool { state.isLoading || monitor.deletingSessions[server.id] != nil }
    private var missing: Bool { state.snapshot?.tmuxHealthy == true && state.currentPane(initialPane.id) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: initialPane.session, subtitle: server.alias + " · Pane " + initialPane.window + "." + initialPane.index, symbol: "terminal") { dismiss() }
            MonitorGlassGroup {
                HStack(spacing: 8) {
                    Toggle("자동 줄바꿈", isOn: $wrap).toggleStyle(.checkbox).font(.callout)
                    Spacer(minLength: 0)
                    GlassIconButton(symbol: copied ? "checkmark" : "doc.on.doc", label: copied ? "로그 복사됨" : "로그 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pane.preview, forType: .string)
                        copied = true
                    }.disabled(pane.preview.isEmpty)
                    GlassIconButton(symbol: "arrow.clockwise", label: "로그 새로고침 · ⌘R") {
                        Task { await monitor.refresh(serverID: server.id) }
                    }.keyboardShortcut("r", modifiers: .command).disabled(!serverEnabled || busy)
                }
            }
            if let error = state.error {
                StatusMessage(symbol: "wifi.exclamationmark", title: "연결 끊김 · 마지막 로그", detail: error, warning: true)
            } else if missing {
                StatusMessage(symbol: "terminal", title: "이 pane이 사라졌습니다", detail: "마지막으로 수집한 로그를 표시합니다.")
            } else if let error = pane.captureError {
                StatusMessage(symbol: "exclamationmark.triangle", title: "로그를 읽지 못했습니다", detail: error, warning: true)
            } else if state.snapshot?.tmuxHealthy == false {
                StatusMessage(symbol: "clock", title: "tmux 갱신 지연 · 마지막 로그")
            }
            logContent
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.mini) }
                Text(!serverEnabled || monitor.paused ? "자동 조회 일시 정지" : "\(Int(monitor.preferences.interval))초마다 갱신")
                Spacer()
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text(updatedText(state.updatedAt, now: context.date)).monospacedDigit()
                }
            }.font(.caption).foregroundStyle(muted)
            Label("읽기 전용 · 원격 터미널에 입력을 보내지 않습니다", systemImage: "lock")
                .font(.caption).foregroundStyle(muted)
        }.padding(20).frame(width: 500, height: 570).background { DashboardBackdrop() }
            .monitorSheetPresentation()
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if !Task.isCancelled { copied = false }
            }
    }

    private var logContent: some View {
        VStack(spacing: 0) {
            if pane.preview.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft").font(.system(size: 24)).foregroundStyle(muted)
                    Text("표시할 로그가 없습니다").font(.system(size: 12)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        ScrollView(wrap ? [.vertical] : [.vertical, .horizontal]) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(pane.preview).font(.system(size: 12, design: .monospaced)).lineSpacing(3)
                                    .textSelection(.enabled).fixedSize(horizontal: !wrap, vertical: true)
                                    .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
                                Color.clear.frame(height: 1).id("log-end")
                            }.padding(14)
                        }
                        HStack {
                            Text("최근 tmux 화면").font(.caption).foregroundStyle(muted)
                            Spacer()
                            Button { proxy.scrollTo("log-end", anchor: .bottomLeading) } label: { AccentLabel(title: "맨 아래", symbol: "arrow.down.to.line") }
                                .monitorAction().controlSize(.small)
                        }.padding(.horizontal, 12).padding(.bottom, 4)
                    }.onAppear { proxy.scrollTo("log-end", anchor: .bottomLeading) }
                        .onChange(of: wrap) { _ in proxy.scrollTo("log-end", anchor: .bottomLeading) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).monitorSurface(.well, radius: 12)
    }
}
