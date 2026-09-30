import BudsCore
import SwiftUI

struct SoundSection: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing16) {
            // The equalizer annotation rides on the section title's baseline instead of
            // holding a row of its own, which is one whole row of height the panel gets back.
            HStack(alignment: .firstTextBaseline, spacing: PanelDesignTokens.spacing8) {
                SectionHeader("音效")
                Spacer(minLength: PanelDesignTokens.spacing8)
                if buds.supportsEqualizer {
                    Label("大师调音", systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel("大师调音")
                }
            }

            if buds.supportsEqualizer {
                VStack(alignment: .leading, spacing: PanelDesignTokens.spacing12) {
                    CompactSegmentedControl(
                        values: EQPreset.allCases,
                        selection: currentEqualizer,
                        pendingValue: buds.pendingEqualizer,
                        size: .secondary,
                        isEnabled: canControlSoundFeatures,
                        isBusy: isEqualizerPending,
                        accessibilityLabel: "均衡器预设",
                        label: { $0.label },
                        action: { buds.set(equalizer: $0) })

                    featureStatus(
                        buds.equalizerFeature,
                        refresh: buds.soundRefresh[.equalizer] ?? .idle,
                        pending: isEqualizerPending,
                        loadingText: "正在读取均衡器…")
                    if let message = buds.operations[.equalizer]?.phase.message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    if case .ready(let curves) = buds.customEqualizerFeature,
                       let selected = curves.first(where: \.isSelected) {
                        Text("自定义：\(selected.name)").font(.caption).foregroundStyle(.secondary)
                    } else if buds.unknownEqualizerMode != nil {
                        Text("当前均衡器模式暂未识别")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if buds.supportsCustomEqualizer {
                        Button {
                            buds.onCustomEqualizerRequested?()
                        } label: {
                            HStack(spacing: PanelDesignTokens.spacing8) {
                                Image(systemName: "slider.vertical.3")
                                    .foregroundStyle(.secondary)
                                Text("自定义均衡器")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, PanelDesignTokens.spacing12)
                            .frame(height: PanelDesignTokens.primaryControlHeight)
                            .background(.primary.opacity(PanelDesignTokens.controlFillOpacity),
                                        in: RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PanelPressButtonStyle())
                        .help("编辑耳机曲线或 Mac 本地方案")
                    }
                }
            }

            if buds.supportsEqualizer && buds.supportsGameMode {
                Divider()
                    .opacity(PanelDesignTokens.dividerOpacity)
            }

            if buds.supportsGameMode {
                gameModeRow
            }
        }
    }

    private var gameModeRow: some View {
        HStack(alignment: .top, spacing: PanelDesignTokens.spacing12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PanelDesignTokens.spacing4) {
                Text("游戏模式")
                    .font(.subheadline.weight(.medium))
                Text("降低游戏声音延迟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                featureStatus(
                    buds.gameModeFeature,
                    refresh: buds.soundRefresh[.gameMode] ?? .idle,
                    pending: isGameModePending,
                    loadingText: "正在读取游戏模式…")
                if let message = buds.operations[.gameMode]?.phase.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: PanelDesignTokens.spacing8)

            if let currentGameMode {
                ZStack {
                    if isGameModePending {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("正在同步游戏模式")
                            .transition(.opacity.animation(MotionTokens.feedback))
                    }
                }
                .frame(width: 16, height: 16)

                Toggle("游戏模式", isOn: Binding(
                    get: { currentGameMode },
                    set: { buds.set(gameMode: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(!canControlSoundFeatures || isGameModePending)
                    .accessibilityLabel("游戏模式")
                    .accessibilityValue(isGameModePending
                        ? "正在同步，当前" + (currentGameMode ? "已开启" : "已关闭")
                        : (currentGameMode ? "已开启" : "已关闭"))
            }
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

    private var isEqualizerPending: Bool {
        buds.pendingEqualizer != nil || buds.operations[.equalizer]?.phase.isPending == true
    }

    private var isGameModePending: Bool {
        buds.pendingGameMode != nil || buds.operations[.gameMode]?.phase.isPending == true
    }

    @ViewBuilder
    private func featureStatus<Value>(
        _ state: FeatureState<Value>,
        refresh: FeatureRefreshState,
        pending: Bool,
        loadingText: String
    ) -> some View where Value: Equatable {
        if pending {
            EmptyView()
        } else if case .failed(let message) = refresh {
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("重试") { buds.refreshSoundFeatures(force: true) }.controlSize(.small)
            }
        } else {
            switch state {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(loadingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                HStack(spacing: PanelDesignTokens.spacing8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重试") { buds.refreshSoundFeatures(force: true) }
                        .controlSize(.small)
                }
            case .unknown, .ready, .unsupported:
                EmptyView()
            }
        }
    }
}
