import BudsCore

struct BatteryPresentation: Equatable {
    enum Kind: String, Equatable {
        case left
        case right
        case combined
        case enclosure
    }

    struct Item: Identifiable, Equatable {
        let kind: Kind
        let label: String
        let accessibilityName: String
        let reading: BatteryReading
        let placement: BudsProtocol.BudPlacement?

        var id: String { kind.rawValue }
    }

    let items: [Item]
    let menuBarPercentage: Int?

    init(
        vendor: BatteryState,
        system: BatteryState,
        placement: EarbudsPlacementState
    ) {
        let left = Self.preferred(vendor.left, system.left)
        let right = Self.preferred(vendor.right, system.right)
        let enclosure = Self.preferred(vendor.enclosure, system.enclosure)
        let combined = Self.preferred(vendor.combined, system.combined)

        var projected: [Item] = []
        if left != nil || right != nil {
            if let left {
                projected.append(Item(
                    kind: .left,
                    label: "L",
                    accessibilityName: "左耳",
                    reading: left,
                    placement: placement.left))
            }
            if let right {
                projected.append(Item(
                    kind: .right,
                    label: "R",
                    accessibilityName: "右耳",
                    reading: right,
                    placement: placement.right))
            }
        } else if let combined {
            projected.append(Item(
                kind: .combined,
                label: "耳机",
                accessibilityName: "耳机",
                reading: combined,
                placement: nil))
        }

        if let enclosure {
            projected.append(Item(
                kind: .enclosure,
                label: "盒",
                accessibilityName: "充电盒",
                reading: enclosure,
                placement: nil))
        }

        items = projected
        if let leftLevel = left?.level, let rightLevel = right?.level {
            menuBarPercentage = min(leftLevel, rightLevel)
        } else {
            menuBarPercentage = nil
        }
    }

    private static func preferred(
        _ vendor: BatteryReading?,
        _ system: BatteryReading?
    ) -> BatteryReading? {
        if let vendor, isValid(vendor.level) { return vendor }
        if let system, isValid(system.level) { return system }
        return nil
    }

    private static func isValid(_ level: Int?) -> Bool {
        guard let level else { return false }
        return (0...100).contains(level)
    }
}
