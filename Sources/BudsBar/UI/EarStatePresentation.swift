import BudsCore

/// Placement evidence does not establish wearing or charging; no battery is required.
struct EarStatePresentation {
    let left: String?
    let right: String?

    init(placement: EarbudsPlacementState) {
        left = Self.label("左耳", placement.left)
        right = Self.label("右耳", placement.right)
    }

    private static func label(_ name: String, _ placement: BudsProtocol.BudPlacement?) -> String? {
        switch placement {
        case .inCase: return "\(name) · 盒内"
        case .inUse: return "\(name) · 盒外"
        case nil: return nil
        }
    }
}
