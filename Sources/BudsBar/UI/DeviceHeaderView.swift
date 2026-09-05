import BudsCore
import SwiftUI

struct DeviceHeaderView: View {
    @Bindable var buds: Buds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMorePresented = false
    @State private var isMoreHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing12) {
            HStack(alignment: .top, spacing: PanelDesignTokens.spacing12) {
                EarbudsArtworkView(size: .compact)

                VStack(alignment: .leading, spacing: 5) {
                    deviceName
                    connectionStatus
                }

                Spacer(minLength: PanelDesignTokens.spacing8)

                if buds.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 7)
                        .accessibilityLabel(connectionSummary)
                }

                if !buds.isConnected {
                    Button("连接") { buds.connect() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                        .disabled(
                            buds.isBusy || !buds.isPaired || buds.requiresDeviceSelection)
                        .accessibilityLabel("连接耳机")
                }

                moreButton
            }

            if buds.isConnected {
                BatteryStripView(buds: buds)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var deviceName: some View {
        if buds.availableDevices.count > 1 && !buds.isDeviceSelectionLocked {
            Menu {
                ForEach(buds.availableDevices) { device in
                    Button {
                        buds.selectDevice(address: device.id)
                    } label: {
                        if device.id == buds.selectedDeviceAddress {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                deviceNameLabel(withChevron: true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(buds.isBusy)
            .layoutPriority(1)
            .accessibilityLabel("选择耳机，当前为\(buds.name)")
        } else {
            deviceNameLabel(withChevron: false)
                .layoutPriority(1)
                .accessibilityLabel("设备名称，\(buds.name)")
        }
    }

    private func deviceNameLabel(withChevron: Bool) -> some View {
        HStack(spacing: PanelDesignTokens.spacing4) {
            Text(buds.name)
                .font(.system(size: PanelDesignTokens.deviceNameSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if withChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(connectionSummary)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(connectionColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(connectionColor.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("连接状态，\(connectionSummary)")
    }

    private var connectionColor: Color {
        if buds.isBusy { return .orange }
        if buds.isConnected { return .green }
        return .secondary
    }

    private var connectionSummary: String {
        if buds.requiresDeviceSelection { return "请选择设备" }
        guard buds.isPaired else { return "未配对" }
        if buds.isBusy { return buds.isConnected ? "正在断开" : "正在连接" }
        guard buds.isConnected else { return "未连接" }
        return "已连接"
    }

    private var moreButton: some View {
        let highlighted = isMoreHovered || isMorePresented

        return Button {
            isMorePresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: PanelDesignTokens.moreButtonSymbolSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(
                    width: PanelDesignTokens.moreButtonVisualSize,
                    height: PanelDesignTokens.moreButtonVisualSize)
                .background {
                    Capsule()
                        .fill(.thinMaterial)
                        .opacity(highlighted ? 1 : 0)
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.primary.opacity(PanelDesignTokens.hairlineOpacity),
                                    lineWidth: 1)
                                .opacity(highlighted ? 1 : 0)
                        }
                }
        }
        .buttonStyle(.plain)
        .frame(width: PanelDesignTokens.moreButtonHitSize, height: PanelDesignTokens.moreButtonHitSize)
        .contentShape(.rect)
        .onHover { isMoreHovered = $0 }
        .animation(MotionTokens.state(reduceMotion: reduceMotion), value: highlighted)
        .accessibilityLabel("详情")
        .help("详情")
        .popover(
            isPresented: $isMorePresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            MoreOptionsView(buds: buds)
        }
    }
}

enum DeviceInformationRefreshFeedback {
    static func nextTrigger(current: Int, didEnqueue: Bool) -> Int {
        didEnqueue ? current + 1 : current
    }
}

private struct MoreOptionsView: View {
    @Bindable var buds: Buds
    @State private var deviceInformationRefreshTrigger = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PanelDesignTokens.inspectorGroupSpacing) {
                if buds.supportsDeviceInformation {
                    inspectorGroup("设备") {
                        deviceInformation
                        Button {
                            deviceInformationRefreshTrigger =
                                DeviceInformationRefreshFeedback.nextTrigger(
                                    current: deviceInformationRefreshTrigger,
                                    didEnqueue: buds.refreshDeviceInformation())
                        } label: {
                            Label {
                                Text("刷新设备信息")
                            } icon: {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(
                                        .rotate,
                                        value: deviceInformationRefreshTrigger)
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(Color.accentColor)
                        .disabled(!buds.isConnected)
                    }
                }

                inspectorGroup("连接") {
                    if buds.isConnected {
                        Button {
                            buds.disconnect()
                        } label: {
                            Label("断开连接", systemImage: "power")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    } else {
                        Button {
                            buds.connect()
                        } label: {
                            Label("连接耳机", systemImage: "link")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(Color.accentColor)
                        .disabled(
                            buds.isBusy || !buds.isPaired || buds.requiresDeviceSelection)
                    }
                }

                inspectorGroup("偏好") {
                    settingRow("显示 Dock 图标", isOn: Binding(
                        get: { buds.dockIconEnabled },
                        set: { buds.setDockIconEnabled($0) }))
                        .help("关闭后仍可从菜单栏打开设置")
                    settingRow("开机自动启动", isOn: Binding(
                        get: { buds.launchesAtLogin },
                        set: { buds.setLaunchAtLogin($0) }))
                    settingRow("低电量通知", isOn: Binding(
                        get: { buds.lowBatteryNotificationsEnabled },
                        set: { buds.setLowBatteryNotifications($0) }))
                }

                inspectorGroup("连接体验") {
                    settingRow("连接状态浮窗", isOn: Binding(
                        get: { buds.connectHUDEnabled },
                        set: { buds.setConnectHUDEnabled($0) }))
                    settingRow("重新连接浮窗", isOn: Binding(
                        get: { buds.reconnectHUDEnabled },
                        set: { buds.setReconnectHUDEnabled($0) }))
                    settingRow("意外断开浮窗", isOn: Binding(
                        get: { buds.unexpectedDisconnectHUDEnabled },
                        set: { buds.setUnexpectedDisconnectHUDEnabled($0) }))
                }

                inspectorGroup("菜单栏") {
                    settingRow("显示左右耳最低电量", isOn: Binding(
                        get: { buds.menuBarBatteryEnabled },
                        set: { buds.setMenuBarBatteryEnabled($0) }))
                }

                inspectorGroup("关于") {
                    HStack {
                        Button("v1.3 新功能") { buds.showWhatsNew() }
                            .buttonStyle(.borderless)
                        Spacer()
                        Button("退出") { NSApplication.shared.terminate(nil) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    .font(.callout)
                }
            }
            .padding(PanelDesignTokens.spacing20)
        }
        .frame(width: PanelDesignTokens.inspectorWidth)
        .frame(maxHeight: PanelDesignTokens.inspectorMaximumHeight)
        .scrollIndicators(.hidden)
        .presentationBackground(.thinMaterial)
    }

    private func inspectorGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing8) {
            Text(title)
                .font(.system(size: PanelDesignTokens.inspectorGroupTitleSize, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.9))
            VStack(alignment: .leading, spacing: PanelDesignTokens.inspectorRowSpacing) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var deviceInformation: some View {
        switch buds.deviceInformationFeature {
        case .ready(let information):
            LabeledContent("型号", value: information.modelIdentifier.value)
                .font(.callout)
            LabeledContent("固件", value: information.firmwareVersion.value)
                .font(.callout)
        case .loading:
            Label("正在读取设备信息…", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        case .unknown:
            Text("设备信息尚未读取")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .unsupported:
            EmptyView()
        }
    }

    private func settingRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: PanelDesignTokens.spacing12) {
            Text(title)
                .font(.callout)
            Spacer(minLength: PanelDesignTokens.spacing8)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(title)
        }
        .frame(minHeight: PanelDesignTokens.inspectorRowMinHeight)
    }
}
