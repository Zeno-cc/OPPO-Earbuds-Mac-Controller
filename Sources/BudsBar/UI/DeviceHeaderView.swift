import BudsCore
import SwiftUI

struct DeviceHeaderView: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing12) {
            HStack(spacing: PanelDesignTokens.spacing8) {
                VStack(alignment: .leading, spacing: 3) {
                    deviceName
                    connectionStatus
                }

                Spacer(minLength: PanelDesignTokens.spacing8)

                if buds.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(connectionSummary)
                }

                if !buds.isConnected {
                    Button("连接") { buds.connect() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(
                            buds.isBusy || !buds.isPaired || buds.requiresDeviceSelection)
                        .accessibilityLabel("连接耳机")
                }

                moreMenu
            }

            if buds.isConnected {
                BatteryStripView(buds: buds)
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
                HStack(spacing: PanelDesignTokens.spacing4) {
                    Text(buds.name)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(buds.isBusy)
            .layoutPriority(1)
            .accessibilityLabel("选择耳机，当前为\(buds.name)")
        } else {
            Text(buds.name)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
                .accessibilityLabel("设备名称，\(buds.name)")
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(connectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

    private var moreMenu: some View {
        Menu {
            if buds.supportsDeviceInformation {
                Section("设备信息") {
                    deviceInformationMenu
                    Button("刷新设备信息") { buds.refreshDeviceInformation() }
                        .disabled(!buds.isConnected)
                }
                Divider()
            }

            if buds.isConnected {
                Button("断开连接") { buds.disconnect() }
            } else {
                Button("连接耳机") { buds.connect() }
                    .disabled(
                        buds.isBusy || !buds.isPaired || buds.requiresDeviceSelection)
            }

            Divider()
            Toggle("开机自动启动", isOn: Binding(
                get: { buds.launchesAtLogin },
                set: { buds.setLaunchAtLogin($0) }))
            Toggle("低电量通知", isOn: Binding(
                get: { buds.lowBatteryNotificationsEnabled },
                set: { buds.setLowBatteryNotifications($0) }))
            Divider()
            Button("退出耳机控制") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("更多")
    }

    @ViewBuilder
    private var deviceInformationMenu: some View {
        switch buds.deviceInformationFeature {
        case .ready(let information):
            Text("型号：\(information.modelIdentifier.value)")
            Text("固件：\(information.firmwareVersion.value)")
        case .loading:
            Text("正在读取设备信息…")
        case .failed(let message):
            Text(message)
        case .unknown:
            Text("设备信息尚未读取")
        case .unsupported:
            EmptyView()
        }
    }
}
