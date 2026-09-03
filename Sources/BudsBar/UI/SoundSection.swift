import BudsCore
import SwiftUI

struct SoundSection: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing12) {
            SectionHeader("音效")

            if buds.supportsEqualizer {
                VStack(alignment: .leading, spacing: PanelDesignTokens.spacing8) {
                    Text("大师调音")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    CompactSegmentedControl(
                        values: EQPreset.allCases,
                        selection: currentEqualizer,
                        pendingValue: buds.pendingEqualizer,
                        size: .secondary,
                        isEnabled: canControlSoundFeatures,
                        accessibilityLabel: "均衡器预设",
                        label: { $0.label },
                        action: { buds.set(equalizer: $0) })

                    featureStatus(
                        buds.equalizerFeature,
                        pending: buds.pendingEqualizer != nil,
                        loadingText: "正在读取均衡器…")
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
        HStack(alignment: .center, spacing: PanelDesignTokens.spacing12) {
            VStack(alignment: .leading, spacing: PanelDesignTokens.spacing4) {
                Text("游戏模式")
                    .font(.callout.weight(.medium))
                Text("降低游戏声音延迟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                featureStatus(
                    buds.gameModeFeature,
                    pending: buds.pendingGameMode != nil,
                    loadingText: "正在读取游戏模式…")
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
        pending: Bool,
        loadingText: String
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
                HStack(spacing: PanelDesignTokens.spacing8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重试") { buds.refreshSoundFeatures(force: true) }
                        .controlSize(.small)
                }
            case .ready, .unsupported:
                EmptyView()
            }
        }
    }
}
