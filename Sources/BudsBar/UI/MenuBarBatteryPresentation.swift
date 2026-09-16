import BudsCore
import Foundation

struct MenuBarBatteryPresentation: Equatable {
    struct Slot: Equatable {
        let slot: BudsProtocol.BatterySlot
        let level: Int?
        let isCharging: Bool?
    }

    let slots: [Slot]
    /// Two lines: the buds stack vertically so the item stays narrow. The case rides along
    /// the second line and only appears once it has a level of its own, because a third line
    /// would not fit the menu bar.
    let text: String?
    let tooltip: String?

    /// Only per-slot vendor observations feed this projection. The aggregate
    /// (`combined`) and macOS accessory readings are deliberately absent: they cannot
    /// establish which bud a percentage belongs to.
    init(observations: [BudsProtocol.BatterySlot: BatterySlotObservation],
         generation: UInt64, now: TimeInterval, freshness: TimeInterval = 45) {
        let order: [BudsProtocol.BatterySlot] = [.left, .right, .enclosure]
        slots = order.map { slot in
            guard let observation = observations[slot], observation.generation == generation,
                  now - observation.observedAt <= freshness,
                  let reading = observation.reading else {
                return Slot(slot: slot, level: nil, isCharging: nil)
            }
            let level = reading.level.flatMap { (0...100).contains($0) ? $0 : nil }
            return Slot(slot: slot, level: level, isCharging: reading.isCharging)
        }
        let hasObservation = slots.contains { $0.level != nil }
        guard hasObservation else {
            text = nil
            tooltip = nil
            return
        }
        func line(_ slot: Slot) -> String {
            let label = slot.slot == .left ? "L" : slot.slot == .right ? "R" : "C"
            guard let level = slot.level else { return "\(label) —" }
            return "\(label) \(level)%\(slot.isCharging == true ? " ⚡" : "")"
        }
        let left = slots[0], right = slots[1], box = slots[2]
        var secondLine = line(right)
        if box.level != nil { secondLine += "  " + line(box) }
        text = line(left) + "\n" + secondLine

        func describe(_ slot: Slot) -> String {
            let label = slot.slot == .left ? "左耳" : slot.slot == .right ? "右耳" : "充电盒"
            guard let level = slot.level else { return "\(label) 未知" }
            return "\(label) \(level)%\(slot.isCharging == true ? "（充电中）" : "")"
        }
        var described = [describe(left), describe(right)]
        if box.level != nil { described.append(describe(box)) }
        tooltip = described.joined(separator: " · ")
    }
}
