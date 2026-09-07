import BudsCore
import SwiftUI

struct SoundSection: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing16) {
            SectionHeader("音效")

            if buds.supportsEqualizer {
                VStack(alignment: .leading, spacing: PanelDesignTokens.spacing12) {
                    HStack(spacing: PanelDesignTokens.spacing8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("大师调音")
                            .font(.subheadline.weight(.medium))
                    }

                    CompactSegmentedControl(
                        values: EQPreset.allCases,
                        selection: currentEqualizer,
                        pendingValue: buds.pendingEqualizer,
                        size: .secondary,
                        isEnabled: canControlSoundFeatures && buds.operations[.equalizer]?.phase.isPending != true,
                        accessibilityLabel: "均衡器预设",
                        label: { $0.label },
                        action: { buds.set(equalizer: $0) })

                    featureStatus(
                        buds.equalizerFeature,
                        refresh: buds.soundRefresh[.equalizer] ?? .idle,
                        pending: buds.pendingEqualizer != nil,
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
                        .buttonStyle(.plain)
                        .disabled(!buds.isControlChannelOpen)
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
                    pending: buds.pendingGameMode != nil,
                    loadingText: "正在读取游戏模式…")
                if let message = buds.operations[.gameMode]?.phase.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: PanelDesignTokens.spacing8)

            if let currentGameMode {
                if buds.pendingGameMode != nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在同步游戏模式")
                }

                Toggle("游戏模式", isOn: Binding(
                    get: { currentGameMode },
                    set: { buds.set(gameMode: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(!canControlSoundFeatures || buds.pendingGameMode != nil)
                    .accessibilityLabel("游戏模式")
                    .accessibilityValue(currentGameMode ? "已开启" : "已关闭")
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

    @ViewBuilder
    private func featureStatus<Value>(
        _ state: FeatureState<Value>,
        refresh: FeatureRefreshState,
        pending: Bool,
        loadingText: String
    ) -> some View where Value: Equatable {
        if pending {
            Text("正在同步…")
                .font(.caption)
                .foregroundStyle(.secondary)
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
