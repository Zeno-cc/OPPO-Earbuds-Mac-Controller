import BudsCore
import SwiftUI

struct NoiseControlSection: View {
    @Bindable var buds: Buds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing12) {
            HStack {
                SectionHeader("降噪")
                Spacer()
                NoiseHelpPopover()
            }

            CompactSegmentedControl(
                values: NoiseMode.allCases,
                selection: buds.mode,
                size: .primary,
                isEnabled: canSwitchModes,
                accessibilityLabel: "降噪模式",
                label: { $0.label },
                action: { buds.set(mode: $0) })

            if buds.mode == .noiseCancellation {
                VStack(alignment: .leading, spacing: 6) {
                    Text("降噪强度")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    CompactSegmentedControl(
                        values: ANCLevel.allCases,
                        selection: buds.ancLevel,
                        size: .secondary,
                        isEnabled: canSwitchModes,
                        accessibilityLabel: "降噪强度",
                        label: { $0.label },
                        action: { buds.set(ancLevel: $0) })

                    Text(buds.ancLevel?.detail ?? "降噪强度未知")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }

            if let note = modeSwitchingNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(
            PanelDesignTokens.stateAnimation(reduceMotion: reduceMotion),
            value: buds.mode)
    }

    private var canSwitchModes: Bool {
        buds.isControlChannelOpen && buds.supportsNoiseControl
    }

    private var modeSwitchingNote: String? {
        if !buds.supportsNoiseControl { return "此耳机型号尚未适配降噪控制" }
        return buds.isControlChannelOpen ? nil : "正在等待控制通道…"
    }
}
