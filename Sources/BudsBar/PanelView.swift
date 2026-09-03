import BudsCore
import SwiftUI

struct PanelView: View {
    @Bindable var buds: Buds
    @State private var showingHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fixedStatusArea

            if buds.isConnected {
                Divider()
                    .opacity(0.45)
                controlArea
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    disconnectedNote
                    panelError
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 368)
        .frame(maxHeight: 556, alignment: .top)
        .background(.ultraThinMaterial)
        // The popover re-adds this view to a window each time it opens, so onAppear is a
        // per-open hook: the panel always shows live state, not whatever it last rendered.
        .onAppear {
            buds.refreshConnectionState()
            buds.refreshBattery()
            buds.refreshSoundFeatures(force: true)
            buds.refreshLaunchAtLoginState()
        }
        .animation(.smooth(duration: 0.28), value: buds.isConnected)
        .animation(.smooth(duration: 0.28), value: buds.battery.enclosure == nil)
        .animation(.smooth(duration: 0.28), value: buds.deviceInformationFeature)
        .animation(.smooth(duration: 0.28), value: buds.systemBattery)
        .animation(.smooth(duration: 0.28), value: buds.placement.left)
        .animation(.smooth(duration: 0.28), value: buds.placement.right)
        .animation(.smooth(duration: 0.28), value: buds.mode)
        .animation(.smooth(duration: 0.28), value: buds.ancLevel)
        .animation(.smooth(duration: 0.28), value: buds.equalizerFeature)
        .animation(.smooth(duration: 0.28), value: buds.gameModeFeature)
    }

    /// Status remains visible while the controls scroll. Its own material backing and glass
    /// container keep the scrollable Liquid Glass effects from visually merging into it.
    private var fixedStatusArea: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if buds.isConnected {
                    batteryRow
                    batterySyncStatus
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }

    /// Only the controls scroll. Explicit clipping is necessary because Liquid Glass can
    /// otherwise draw beyond the ScrollView's visual boundary and cover the fixed header.
    private var controlArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if buds.lastError != nil {
                panelError
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                Divider()
                    .opacity(0.35)
            }

            ScrollView(.vertical) {
                GlassEffectContainer(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        if buds.supportsNoiseControl {
                            noiseControlCard
                        } else {
                            unsupportedDeviceCard
                        }
                        if buds.supportsEqualizer || buds.supportsGameMode {
                            soundControlCard
                        }
                    }
                    .padding(14)
                }
            }
            .scrollIndicators(.automatic)
            .scrollClipDisabled(false)
            .clipped()
        }
        .frame(height: preferredControlAreaHeight)
    }

    /// A ScrollView has no useful intrinsic height, so a max-height alone lets the popover
    /// collapse and forces scrolling even when every normal control would fit. Full-featured
    /// devices get the complete Air5 control surface; simpler profiles keep a compact panel.
    private var preferredControlAreaHeight: CGFloat {
        if buds.supportsEqualizer || buds.supportsGameMode { return 398 }
        if buds.supportsNoiseControl { return 230 }
        return 132
    }

    @ViewBuilder
    private var panelError: some View {
        if let error = buds.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
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
                        HStack(spacing: 4) {
                            Text(buds.name)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(buds.isBusy)
                } else {
                    Text(buds.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                Text(connectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if buds.isBusy {
                ProgressView().controlSize(.small)
            }

            Toggle("电源", isOn: Binding(
                get: { buds.isConnected },
                set: { $0 ? buds.connect() : buds.disconnect() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(buds.isBusy || !buds.isPaired)

            Menu {
                if buds.isConnected && buds.supportsDeviceInformation {
                    Section("设备信息") {
                        deviceInformationMenu
                        Button("刷新设备信息") { buds.refreshDeviceInformation() }
                    }
                    Divider()
                }
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
        }
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

    private var connectionSummary: String {
        if buds.requiresDeviceSelection { return "请选择设备" }
        guard buds.isPaired else { return "未配对" }
        guard buds.isConnected else { return "未连接" }
        return "已连接"
    }

    private var disconnectedNote: some View {
        Text(disconnectedMessage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disconnectedMessage: String {
        if buds.requiresDeviceSelection {
            return "检测到多副兼容耳机，请从上方列表选择要控制的设备。"
        }
        if buds.isPaired {
            return "请将耳机从充电盒中取出，然后打开电源开关以连接。"
        }
        return "没有找到支持此协议的已配对耳机。请先在蓝牙设置中配对 realme 或 OPPO 耳机。"
    }

    private var unsupportedDeviceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("此型号尚未适配控制功能", systemImage: "info.circle")
                .font(.callout.weight(.medium))
            Text("当前仍会显示耳机能够上报的电量，但不会发送降噪等型号专用命令。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Battery

    private var batteryRow: some View {
        let left = preferredBatteryReading(buds.battery.left, buds.systemBattery.left)
        let right = preferredBatteryReading(buds.battery.right, buds.systemBattery.right)
        let enclosure = preferredBatteryReading(
            buds.battery.enclosure, buds.systemBattery.enclosure)
        let combined = preferredBatteryReading(
            buds.battery.combined, buds.systemBattery.combined)

        return HStack(spacing: 0) {
            if left?.level != nil || right?.level != nil {
                batteryCell("左耳", glyph: "l.circle", reading: left,
                            placement: buds.placement.left)
                batteryCell("右耳", glyph: "r.circle", reading: right,
                            placement: buds.placement.right)
            } else if combined?.level != nil {
                // macOS may expose only the aggregate headset value. Do not present it as
                // two independent bud readings when the source does not distinguish them.
                batteryCell("耳机", glyph: "airpods.pro", reading: combined)
            } else {
                batteryCell("左耳", glyph: "l.circle", reading: nil,
                            placement: buds.placement.left)
                batteryCell("右耳", glyph: "r.circle", reading: nil,
                            placement: buds.placement.right)
            }
            // The case reports 0% while it is shut or asleep, which `interpret` turns into
            // nil rather than a false flat battery. Its last confirmed value is retained
            // across a short link handoff, because the case often stays asleep after that.
            if enclosure?.level != nil {
                // The charging-case glyph, same one the menu bar uses. `shippingbox` read as
                // a parcel rather than an earbud case.
                batteryCell("充电盒", glyph: "airpods.pro.chargingcase.wireless.fill",
                            reading: enclosure)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func preferredBatteryReading(_ vendor: BatteryReading?,
                                         _ system: BatteryReading?) -> BatteryReading? {
        vendor?.level != nil ? vendor : system
    }

    /// `placement` is nil for the case, and for a bud whose reported value we do not
    /// recognise — both mean "no idea", and the cell is drawn as it always was rather than
    /// guessing. A bud known to be in the case is dimmed — it is stowed, not necessarily
    /// charging — but still shows its percentage while the case is awake and reporting.
    /// A shut case stops reporting, the reading it cleared on the way in is never refilled,
    /// and the cell honestly reads "—%".
    private func batteryCell(_ title: String, glyph: String, reading: BatteryReading?,
                             placement: BudsProtocol.BudPlacement? = nil) -> some View {
        let level = reading?.level
        let isCharging = reading?.isCharging == true
        let stowed = placement == .inCase
        let muted = stowed || level == nil
        let meterColor: Color = isCharging ? .green : (muted ? .secondary : .primary)
        let accessibilityDescription = level.map {
            "\(title)电量\($0)%\(isCharging ? "，正在充电" : "")\(stowed ? "，位于充电盒内" : "")"
        } ?? "\(title)电量未知"

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(stowed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

            HStack(spacing: 4) {
                // No glyph without a reading: a battery symbol would draw a level we do not
                // have.
                if let level {
                    Image(systemName: batterySymbol(for: level))
                        .font(.system(size: 13))
                        .foregroundStyle(meterColor)
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
                Text(level.map { "\($0)%" } ?? "—%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(meterColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func batterySymbol(for level: Int?) -> String {
        guard let level else { return "battery.0percent" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    @ViewBuilder
    private var batterySyncStatus: some View {
        switch buds.batteryFeature {
        case .loading where !hasVisibleBattery:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在读取电量…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message) where !hasVisibleBattery:
            HStack(spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("重试") { buds.refreshBattery(force: true) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        default:
            EmptyView()
        }
    }

    private var hasVisibleBattery: Bool {
        batteryValues.contains { $0 != nil }
    }

    private var batteryValues: [Int?] {
        [buds.battery.left?.level ?? buds.systemBattery.left?.level,
         buds.battery.right?.level ?? buds.systemBattery.right?.level,
         buds.battery.enclosure?.level ?? buds.systemBattery.enclosure?.level,
         buds.battery.combined?.level ?? buds.systemBattery.combined?.level]
    }

    // MARK: - Noise control

    private var noiseControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("降噪控制")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        showingHelp.toggle()
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(showingHelp ? "收起降噪说明" : "显示降噪说明")
            }

            if showingHelp {
                Text("降噪可阻隔外界声音；深度、中度、轻度适合不同环境，智能会自动选择强度。通透用于听见周围声音，关闭则停用两种模式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 8) {
                ForEach(NoiseMode.allCases) { mode in
                    noiseButton(mode)
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(!canSwitchModes)
            .opacity(canSwitchModes ? 1 : 0.45)

            if buds.mode == .noiseCancellation {
                ancLevelPicker
            }

            if let note = modeSwitchingNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    /// Shown only while noise cancellation is the active mode, since the level is
    /// meaningless otherwise. Air5 Pro and T500 Pro both report Smart as a real ANC level;
    /// the picker keeps it selectable instead of collapsing it into an unknown state.
    private var ancLevelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Hand-rolled rather than a segmented Picker: on macOS that control sizes itself
            // to its widest label and will not stretch, so the row never filled the card.
            HStack(spacing: 6) {
                ForEach(ANCLevel.allCases) { level in
                    levelSegment(level)
                }
            }
            .frame(maxWidth: .infinity)

            Text(buds.ancLevel?.detail ?? "降噪强度未知")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!canSwitchModes)
        .opacity(canSwitchModes ? 1 : 0.45)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// One level, sized to an equal share of the row.
    private func levelSegment(_ level: ANCLevel) -> some View {
        let selected = buds.ancLevel == level
        return Button {
            buds.set(ancLevel: level)
        } label: {
            Text(level.label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .glassEffect(
                    selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                    in: .capsule)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var canSwitchModes: Bool {
        buds.isControlChannelOpen && buds.supportsNoiseControl
    }

    private var modeSwitchingNote: String? {
        if !buds.supportsNoiseControl { return "此耳机型号尚未适配降噪控制" }
        return buds.isControlChannelOpen ? nil : "正在等待控制通道…"
    }

    private func noiseButton(_ mode: NoiseMode) -> some View {
        let selected = buds.mode == mode
        return Button {
            buds.set(mode: mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 44, height: 44)
                    .glassEffect(
                        selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .circle)

                Text(mode.label)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Equalizer and game mode

    private var soundControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("音效")
                .font(.system(size: 15, weight: .semibold))

            if buds.supportsEqualizer {
                VStack(alignment: .leading, spacing: 8) {
                    Text("大师调音")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(EQPreset.allCases) { preset in
                            equalizerSegment(preset)
                        }
                    }

                    featureStatus(
                        buds.equalizerFeature,
                        pending: buds.pendingEqualizer != nil,
                        loadingText: "正在读取均衡器…",
                        retry: { buds.refreshSoundFeatures(force: true) })
                }
            }

            if buds.supportsEqualizer && buds.supportsGameMode {
                Divider()
            }

            if buds.supportsGameMode {
                gameModeRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func equalizerSegment(_ preset: EQPreset) -> some View {
        let selected = currentEqualizer == preset
        return Button {
            buds.set(equalizer: preset)
        } label: {
            Text(preset.label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .glassEffect(
                    selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                    in: .capsule)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canControlSoundFeatures || buds.pendingEqualizer != nil)
        .opacity(canControlSoundFeatures ? 1 : 0.45)
        .accessibilityLabel(preset.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var gameModeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("游戏模式")
                    .font(.callout.weight(.medium))
                Text("降低游戏声音延迟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                featureStatus(
                    buds.gameModeFeature,
                    pending: buds.pendingGameMode != nil,
                    loadingText: "正在读取游戏模式…",
                    retry: { buds.refreshSoundFeatures(force: true) })
            }
            Spacer(minLength: 8)
            Toggle("游戏模式", isOn: Binding(
                get: { currentGameMode ?? false },
                set: { buds.set(gameMode: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!canControlSoundFeatures || buds.pendingGameMode != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentEqualizer: EQPreset? {
        guard case .ready(let preset) = buds.equalizerFeature else { return nil }
        return preset
    }

    private var currentGameMode: Bool? {
        guard case .ready(let enabled) = buds.gameModeFeature else { return nil }
        return enabled
    }

    private var canControlSoundFeatures: Bool {
        buds.isControlChannelOpen
    }

    @ViewBuilder
    private func featureStatus<Value>(
        _ state: FeatureState<Value>,
        pending: Bool,
        loadingText: String,
        retry: @escaping () -> Void
    ) -> some View where Value: Equatable {
        if pending {
            Text("正在同步…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch state {
            case .loading, .unknown:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(loadingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                HStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重试", action: retry)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            case .ready, .unsupported:
                EmptyView()
            }
        }
    }
}
