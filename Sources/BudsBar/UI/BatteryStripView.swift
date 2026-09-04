import BudsCore
import SwiftUI

struct BatteryStripView: View {
    @Bindable var buds: Buds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if buds.batteryPresentation.items.isEmpty {
            batteryStatus
        } else {
            HStack(spacing: 0) {
                ForEach(buds.batteryPresentation.items) { item in
                    batteryItem(item)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func batteryItem(_ item: BatteryPresentation.Item) -> some View {
        let level = item.reading.level
        let isCharging = item.reading.isCharging == true
        let isStowed = item.placement == .inCase
        let accessibilityDescription = level.map {
            "\(item.accessibilityName)电量\($0)%\(isCharging ? "，正在充电" : "")"
                + (isStowed ? "，位于充电盒内" : "")
        } ?? "\(item.accessibilityName)电量未知"

        return VStack(alignment: .leading, spacing: PanelDesignTokens.spacing4) {
            HStack(spacing: PanelDesignTokens.spacing4) {
                Text(item.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            if let level {
                Text("\(level)%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(level)))
                    .foregroundStyle(isStowed ? .secondary : .primary)
                Capsule()
                    .fill(Color.primary.opacity(PanelDesignTokens.batteryTrackOpacity))
                    .frame(
                        width: PanelDesignTokens.batteryBarWidth,
                        height: PanelDesignTokens.batteryBarHeight)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                isCharging
                                    ? Color.green
                                    : Color.accentColor.opacity(PanelDesignTokens.batteryAccentOpacity))
                            .frame(
                                width: PanelDesignTokens.batteryBarWidth * CGFloat(level) / 100,
                                height: PanelDesignTokens.batteryBarHeight)
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PanelDesignTokens.spacing8)
        .padding(.vertical, PanelDesignTokens.spacing4)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .help(item.accessibilityName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .animation(MotionTokens.state(reduceMotion: reduceMotion), value: isCharging)
        .animation(
            reduceMotion ? nil : .easeOut(duration: MotionTokens.battery),
            value: level)
    }

    @ViewBuilder
    private var batteryStatus: some View {
        switch buds.batteryFeature {
        case .loading:
            HStack(spacing: PanelDesignTokens.spacing8) {
                ProgressView().controlSize(.small)
                Text("正在读取电量…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .failed(let message):
            HStack(spacing: PanelDesignTokens.spacing8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: PanelDesignTokens.spacing8)
                Button("重试") { buds.refreshBattery(force: true) }
                    .controlSize(.small)
            }
        case .ready, .unknown, .unsupported:
            EmptyView()
        }
    }

}
