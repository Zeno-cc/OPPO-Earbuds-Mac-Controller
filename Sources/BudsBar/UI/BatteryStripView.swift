import BudsCore
import SwiftUI

struct BatteryStripView: View {
    @Bindable var buds: Buds

    var body: some View {
        if batteryItems.isEmpty {
            batteryStatus
        } else {
            HStack(spacing: PanelDesignTokens.spacing8) {
                ForEach(batteryItems) { item in
                    batteryItem(item)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var batteryItems: [BatteryItem] {
        let left = preferredBatteryReading(buds.battery.left, buds.systemBattery.left)
        let right = preferredBatteryReading(buds.battery.right, buds.systemBattery.right)
        let enclosure = preferredBatteryReading(
            buds.battery.enclosure, buds.systemBattery.enclosure)
        let combined = preferredBatteryReading(
            buds.battery.combined, buds.systemBattery.combined)

        var items: [BatteryItem] = []
        if left?.level != nil || right?.level != nil {
            if let left, left.level != nil {
                items.append(BatteryItem(
                    id: "left",
                    label: "L",
                    accessibilityName: "左耳",
                    reading: left,
                    placement: buds.placement.left))
            }
            if let right, right.level != nil {
                items.append(BatteryItem(
                    id: "right",
                    label: "R",
                    accessibilityName: "右耳",
                    reading: right,
                    placement: buds.placement.right))
            }
        } else if let combined, combined.level != nil {
            items.append(BatteryItem(
                id: "combined",
                label: "耳机",
                accessibilityName: "耳机",
                reading: combined))
        }

        if let enclosure, enclosure.level != nil {
            items.append(BatteryItem(
                id: "enclosure",
                label: "盒",
                accessibilityName: "充电盒",
                reading: enclosure))
        }
        return items
    }

    private func preferredBatteryReading(
        _ vendor: BatteryReading?,
        _ system: BatteryReading?
    ) -> BatteryReading? {
        vendor?.level != nil ? vendor : system
    }

    private func batteryItem(_ item: BatteryItem) -> some View {
        let level = item.reading.level
        let isCharging = item.reading.isCharging == true
        let isStowed = item.placement == .inCase
        let accessibilityDescription = level.map {
            "\(item.accessibilityName)电量\($0)%\(isCharging ? "，正在充电" : "")"
                + (isStowed ? "，位于充电盒内" : "")
        } ?? "\(item.accessibilityName)电量未知"

        return HStack(spacing: PanelDesignTokens.spacing4) {
            Text(item.label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
            if let level {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text("\(level)%")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isStowed ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .help(item.accessibilityName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
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

private struct BatteryItem: Identifiable {
    let id: String
    let label: String
    let accessibilityName: String
    let reading: BatteryReading
    var placement: BudsProtocol.BudPlacement?
}
