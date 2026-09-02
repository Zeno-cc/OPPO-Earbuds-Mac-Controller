import SwiftUI

struct PanelView: View {
    @Bindable var buds: Buds
    @State private var showingHelp = false

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if buds.isConnected {
                    batteryRow
                    noiseControlCard
                } else {
                    disconnectedNote
                }
                if let error = buds.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        // The popover re-adds this view to a window each time it opens, so onAppear is a
        // per-open hook: the panel always shows live state, not whatever it last rendered.
        .onAppear {
            buds.refreshConnectionState()
            buds.refreshLaunchAtLoginState()
        }
        .animation(.smooth(duration: 0.28), value: buds.isConnected)
        .animation(.smooth(duration: 0.28), value: buds.battery.enclosure == nil)
        .animation(.smooth(duration: 0.28), value: buds.systemBattery)
        .animation(.smooth(duration: 0.28), value: buds.placement.left)
        .animation(.smooth(duration: 0.28), value: buds.placement.right)
        .animation(.smooth(duration: 0.28), value: buds.mode)
        .animation(.smooth(duration: 0.28), value: buds.ancLevel)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(buds.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(buds.isPaired ? (buds.isConnected ? "已连接" : "未连接")
                                   : "未配对")
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
                Toggle("开机自动启动", isOn: Binding(
                    get: { buds.launchesAtLogin },
                    set: { buds.setLaunchAtLogin($0) }))
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

    private var disconnectedNote: some View {
        Text(buds.isPaired
             ? "请将耳机从充电盒中取出，然后打开电源开关以连接。"
             : "没有找到支持此协议的已配对耳机。请先在蓝牙设置中配对 realme 或 OPPO 耳机。")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Battery

    private var batteryRow: some View {
        let left = buds.battery.left ?? buds.systemBattery.left
        let right = buds.battery.right ?? buds.systemBattery.right
        let enclosure = buds.battery.enclosure ?? buds.systemBattery.enclosure
        let combined = buds.battery.combined ?? buds.systemBattery.combined

        return HStack(spacing: 0) {
            if left != nil || right != nil {
                batteryCell("左耳", glyph: "l.circle", level: left,
                            placement: buds.placement.left)
                batteryCell("右耳", glyph: "r.circle", level: right,
                            placement: buds.placement.right)
            } else if combined != nil {
                // macOS may expose only the aggregate headset value. Do not present it as
                // two independent bud readings when the source does not distinguish them.
                batteryCell("耳机", glyph: "airpods.pro", level: combined)
            } else {
                batteryCell("左耳", glyph: "l.circle", level: nil,
                            placement: buds.placement.left)
                batteryCell("右耳", glyph: "r.circle", level: nil,
                            placement: buds.placement.right)
            }
            // The case reports 0% while it is shut or asleep, which `interpret` turns into
            // nil rather than a false flat battery. Its last confirmed value is retained
            // across a short link handoff, because the case often stays asleep after that.
            if enclosure != nil {
                // The charging-case glyph, same one the menu bar uses. `shippingbox` read as
                // a parcel rather than an earbud case.
                batteryCell("充电盒", glyph: "airpods.pro.chargingcase.wireless.fill",
                            level: enclosure)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// `placement` is nil for the case, and for a bud whose reported value we do not
    /// recognise — both mean "no idea", and the cell is drawn as it always was rather than
    /// guessing. A bud known to be in the case is dimmed — it is charging, not in use — but
    /// still shows its percentage while the case is awake and reporting. A shut case stops
    /// reporting, the reading it cleared on the way in is never refilled, and the cell then
    /// honestly reads "—%".
    private func batteryCell(_ title: String, glyph: String, level: Int?,
                             placement: BudsProtocol.BudPlacement? = nil) -> some View {
        let stowed = placement == .inCase
        let muted = stowed || level == nil
        return VStack(spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 30, height: 30)
                .foregroundStyle(stowed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .glassEffect(.regular, in: .circle)

            HStack(spacing: 4) {
                // No glyph without a reading: a battery symbol would draw a level we do not
                // have.
                if let level {
                    Image(systemName: batterySymbol(for: level))
                        .font(.system(size: 13))
                        .foregroundStyle(muted ? .secondary : .primary)
                }
                Text(level.map { "\($0)%" } ?? "—%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted ? .secondary : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                level.map { "\(title)电量\($0)%\(stowed ? "，位于充电盒内" : "")" }
                     ?? "\(title)电量未知")
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - Noise control

    private var noiseControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("降噪控制")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { showingHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    Text("降噪模式可以阻隔外界声音。深度适合飞机和火车，中度适合街道，轻度适合家庭和办公室。智能会自动选择强度。通透模式可以听见周围声音，关闭模式不启用降噪或通透。")
                        .font(.callout)
                        .frame(width: 240)
                        .padding(12)
                }
            }

            HStack(spacing: 0) {
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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

    private var canSwitchModes: Bool { buds.isControlChannelOpen }

    private var modeSwitchingNote: String? {
        buds.isControlChannelOpen ? nil : "正在等待控制通道…"
    }

    private func noiseButton(_ mode: NoiseMode) -> some View {
        let selected = buds.mode == mode
        return Button {
            buds.set(mode: mode)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 54, height: 54)
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
}
