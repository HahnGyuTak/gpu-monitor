import AppKit
import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: title, symbol: symbol)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).monitorSurface(.panel)
    }
}

struct MenuIconSettingsView: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        SettingsSection(title: "모양과 색상", symbol: "paintpalette") {
            HStack(spacing: 12) {
                Text("메뉴바 아이콘").frame(width: 88, alignment: .leading)
                MonitorSegmentedPicker(label: "아이콘 모양", options: MenuIconStyle.allCases.map { ($0, $0.label) }, selection: Binding(
                    get: { monitor.preferences.menuIconStyle }, set: { monitor.preferences.menuIconStyle = $0; monitor.save() }))
            }
            HStack(spacing: 12) {
                Text("강조색").frame(width: 88, alignment: .leading)
                colorPicker
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Text("미리보기").foregroundStyle(muted).frame(width: 88, alignment: .leading)
                ForEach([4, 6, 8], id: \.self) { count in
                    HStack(spacing: 6) {
                        Image(nsImage: GPUPieIcon.image(for: GPUPieState(server: nil, slices: (0..<count).map {
                            GPUPieSlice(index: $0, active: $0 % 3 != 1)
                        }, status: nil), style: monitor.preferences.menuIconStyle, color: monitor.preferences.menuIconColor))
                            .accessibilityHidden(true)
                        Text("\(count) GPU").font(.caption).foregroundStyle(muted)
                    }.frame(maxWidth: .infinity)
                }
            }.padding(.vertical, 4)
            Text("활성 GPU만 색을 표시합니다. 강조색은 창의 아이콘과 진행 막대에도 적용됩니다.")
                .font(.caption).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
        }.font(.callout)
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            ForEach(MenuIconColor.allCases, id: \.self) { color in
                let selected = monitor.preferences.menuIconColor == color
                let tint = Color(nsColor: MonitorAppearance.iconColor(color))
                Button {
                    monitor.preferences.menuIconColor = color; monitor.save()
                } label: {
                    ZStack {
                        if color == .monochrome {
                            Image(systemName: "circle.lefthalf.filled").font(.system(size: 24)).foregroundStyle(tint)
                        } else {
                            Circle().fill(tint).frame(width: 24, height: 24)
                        }
                        Circle().strokeBorder(selected ? tint : .clear, lineWidth: 2).frame(width: 32, height: 32)
                    }.frame(width: 36, height: 36).contentShape(Circle())
                }.buttonStyle(.borderless).help(color.label).accessibilityLabel("강조 색상 " + color.label)
                    .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("강조색")
    }

}

struct SettingsView: View {
    @ObservedObject var monitor: Monitor
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드" }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MenuIconSettingsView(monitor: monitor)
                    monitoring
                    notifications
                    DisclosureGroup("관측 범위") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GPU 사용률은 서버 전체, 진행률은 로그의 현재 단계 기준입니다. 100%만으로 정상 종료를 판단하지 않습니다.")
                            Text("Mac이 잠들거나 앱이 종료되면 조회가 멈춥니다. 다시 연결해 현재 상태를 확인하지만 그 사이 사라진 로그는 복구하지 못합니다.")
                        }.font(.caption).foregroundStyle(muted).padding(.top, 6)
                    }.font(.callout).padding(12).monitorSurface(.panel)
                }.padding(12).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("GPU Monitor \(version)").font(.caption).foregroundStyle(muted)
                Spacer()
                Button("앱 종료") { NSApplication.shared.terminate(nil) }.monitorAction().controlSize(.small)
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private var monitoring: some View {
        SettingsSection(title: "모니터링", symbol: "waveform.path.ecg") {
            HStack(spacing: 12) {
                Text("조회 간격").frame(width: 88, alignment: .leading)
                Picker("조회 간격", selection: Binding(get: { monitor.preferences.interval }, set: { monitor.preferences.interval = $0; monitor.save() })) {
                    Text("5초").tag(5.0); Text("10초").tag(10.0); Text("30초").tag(30.0); Text("60초").tag(60.0)
                }.pickerStyle(.menu).labelsHidden().frame(width: 90)
                Spacer()
            }
            Toggle("간결한 메뉴바", isOn: Binding(get: { monitor.preferences.compact }, set: { monitor.preferences.compact = $0; monitor.save() }))
                .toggleStyle(.checkbox).help("고정한 실행 작업의 진행률과 ETA만 표시합니다.")
            Text("간결한 표시를 켜면 고정한 실행 작업의 진행률과 ETA만 남깁니다.").font(.caption).foregroundStyle(muted)
        }.font(.callout)
    }

    private var notifications: some View {
        SettingsSection(title: "알림", symbol: "bell") {
            HStack {
                Toggle("macOS 알림", isOn: Binding(get: { monitor.preferences.notifications }, set: { monitor.setNotifications($0) }))
                    .toggleStyle(.checkbox).disabled(monitor.requestingNotifications)
                Spacer()
                Button("알림 테스트") { monitor.testNotification() }.monitorAction().controlSize(.small)
                    .disabled(!monitor.preferences.notifications || monitor.requestingNotifications)
            }
            Text("감시를 켠 pane의 새 오류와 종료를 알립니다. 처음 연결했을 때의 과거 로그는 알리지 않습니다.")
                .font(.caption).foregroundStyle(muted)
            if monitor.requestingNotifications {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("알림 권한 확인 중") }
            }
            if let message = monitor.notificationMessage { StatusMessage(symbol: "info.circle", title: message) }
            if let notice = monitor.lastNotice { StatusMessage(symbol: "clock", title: "최근 이벤트", detail: notice) }
        }.font(.callout)
    }
}
