import AppKit
import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: title, symbol: symbol)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).monitorCard()
    }
}

struct MenuIconSettingsView: View {
    @Environment(\.monitorAccent) private var accent
    @ObservedObject var monitor: Monitor

    var body: some View {
        SettingsSection(title: "모양과 색상", symbol: "paintpalette") {
            VStack(alignment: .leading, spacing: 8) {
                Text("메뉴바 아이콘 모양").font(.system(size: 12, weight: .medium))
                MonitorSegmentedPicker(label: "아이콘 모양", options: MenuIconStyle.allCases.map { ($0, $0.label) }, selection: Binding(
                    get: { monitor.preferences.menuIconStyle },
                    set: { monitor.preferences.menuIconStyle = $0; monitor.save() }))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("강조 색상").font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    ForEach(MenuIconColor.allCases, id: \.self) { color in colorButton(color) }
                }
                Text("메뉴바와 창의 아이콘·진행 막대에 함께 적용됩니다.")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            preview
            Text(monitor.preferences.menuIconStyle == .circles
                 ? "1~8개 GPU를 한 원에 표시합니다. 12시부터 번호순으로 시계 방향입니다."
                 : "왼쪽부터 GPU마다 막대 하나를 표시합니다. 막대 높이는 일정합니다.")
                .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func colorButton(_ color: MenuIconColor) -> some View {
        let selected = monitor.preferences.menuIconColor == color
        return Button {
            monitor.preferences.menuIconColor = color
            monitor.save()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(nsColor: MonitorAppearance.iconColor(color))).frame(width: 22, height: 22)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(nsColor: MonitorAppearance.surface))
                    }
                }
                Text(color.label).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
            }.frame(maxWidth: .infinity).padding(.vertical, 9)
        }.buttonStyle(MonitorButtonStyle(selected: selected, icon: true, embedded: true))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? accent.opacity(0.5) : Color.clear))
            .accessibilityLabel("강조 색상 " + color.label)
            .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var preview: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("미리보기").font(.system(size: 12, weight: .medium))
                Text("활성 GPU만 색 표시").font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            ForEach([4, 6, 8], id: \.self) { count in
                VStack(spacing: 8) {
                    Image(nsImage: GPUPieIcon.image(for: GPUPieState(server: nil, slices: (0..<count).map {
                        GPUPieSlice(index: $0, active: $0 % 3 != 1)
                    }, status: nil), style: monitor.preferences.menuIconStyle, color: monitor.preferences.menuIconColor))
                        .accessibilityHidden(true)
                    Text("\(count) GPU").font(.system(size: 11)).foregroundStyle(muted)
                }.frame(minWidth: 46)
            }
        }.padding(12).background(inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: Monitor
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MenuIconSettingsView(monitor: monitor)
                    monitoring
                    notifications
                    SettingsSection(title: "알아두기", symbol: "info.circle") {
                        Text("GPU 사용률은 서버 전체, 진행률은 로그의 현재 단계 기준입니다. 100%만으로 정상 종료를 판단하지 않습니다.")
                        Text("Mac이 잠들거나 앱이 종료되면 조회가 멈춥니다. 다시 연결해 현재 상태를 확인하지만 그 사이 사라진 로그는 복구하지 못합니다.")
                    }.font(.system(size: 11)).foregroundStyle(muted)
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            HStack {
                Text("GPU Monitor \(version)").font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: { Label("앱 종료", systemImage: "power") }
                    .buttonStyle(MonitorButtonStyle(embedded: true))
            }.padding(.horizontal, 20).padding(.vertical, 8).background(.bar)
        }
    }

    private var monitoring: some View {
        SettingsSection(title: "모니터링", symbol: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 8) {
                Text("자동 조회 간격").font(.system(size: 12, weight: .medium))
                MonitorSegmentedPicker(label: "조회 간격", options: [(5.0, "5초"), (10.0, "10초"), (30.0, "30초"), (60.0, "60초")], selection: Binding(
                    get: { monitor.preferences.interval },
                    set: { monitor.preferences.interval = $0; monitor.save() }))
            }
            Divider().opacity(0.5)
            Toggle(isOn: Binding(get: { monitor.preferences.compact }, set: { monitor.preferences.compact = $0; monitor.save() })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("간결한 메뉴바").font(.system(size: 12, weight: .medium))
                    Text("고정한 실행 작업의 진행률과 ETA만 표시합니다.").font(.system(size: 11)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small).accessibilityLabel("간결한 메뉴바")
        }
    }

    private var notifications: some View {
        SettingsSection(title: "알림", symbol: "bell") {
            Toggle(isOn: Binding(get: { monitor.preferences.notifications }, set: { monitor.setNotifications($0) })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS 알림").font(.system(size: 12, weight: .medium))
                    Text("벨을 켠 pane의 새 오류와 종료를 알립니다.")
                        .font(.system(size: 11)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small).accessibilityLabel("macOS 알림").disabled(monitor.requestingNotifications)
            if monitor.requestingNotifications {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("알림 권한 확인 중") }
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            Text("처음 연결했을 때의 과거 로그는 알리지 않습니다. 시스템 설정에서 GPU Monitor의 알림도 허용해 주세요.")
                .font(.system(size: 11)).foregroundStyle(muted)
            if let message = monitor.notificationMessage {
                StatusMessage(symbol: "info.circle", title: message)
            }
            Button { monitor.testNotification() } label: { Label("테스트 알림 보내기", systemImage: "bell.badge") }
                .buttonStyle(MonitorButtonStyle()).disabled(!monitor.preferences.notifications || monitor.requestingNotifications)
            if let notice = monitor.lastNotice {
                StatusMessage(symbol: "clock", title: "최근 감지한 이벤트", detail: notice)
            }
        }
    }
}
