public enum BatteryComponent: Hashable {
    case left
    case right
    case enclosure
    case combined
}

public enum BatteryAlertSeverity: Equatable {
    case warning
    case critical
}

public struct BatteryAlertReading: Equatable {
    public let component: BatteryComponent
    public let level: Int

    public init(component: BatteryComponent, level: Int) {
        self.component = component
        self.level = level
    }
}

public struct BatteryAlert: Equatable {
    public let severity: BatteryAlertSeverity
    public let readings: [BatteryAlertReading]

    public init(severity: BatteryAlertSeverity, readings: [BatteryAlertReading]) {
        self.severity = severity
        self.readings = readings
    }
}

/// Decides when a fresh battery update deserves a user notification.
///
/// The first reading is only a baseline. A notification is emitted when a component
/// crosses 20% or 10% from above, and a small recovery margin prevents values hovering
/// around either boundary from repeatedly notifying the user.
public struct BatteryNotificationPolicy {
    public let warningThreshold: Int
    public let criticalThreshold: Int
    public let warningResetLevel: Int
    public let criticalResetLevel: Int

    private var lastLevels: [BatteryComponent: Int] = [:]
    private var warningLatched: Set<BatteryComponent> = []
    private var criticalLatched: Set<BatteryComponent> = []

    public init(warningThreshold: Int = 20,
                criticalThreshold: Int = 10,
                warningResetLevel: Int = 25,
                criticalResetLevel: Int = 15) {
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.warningResetLevel = warningResetLevel
        self.criticalResetLevel = criticalResetLevel
    }

    public mutating func reset() {
        lastLevels.removeAll()
        warningLatched.removeAll()
        criticalLatched.removeAll()
    }

    public mutating func evaluate(
        _ state: BatteryState,
        suppressing suppressedComponents: Set<BatteryComponent> = []
    ) -> BatteryAlert? {
        let readings = effectiveReadings(from: state).filter {
            !suppressedComponents.contains($0.0)
        }
        let observed = Set(readings.map(\.0))

        for component in BatteryComponent.allCases where !observed.contains(component) {
            clear(component)
        }

        var crossed: [(BatteryAlertReading, BatteryAlertSeverity)] = []
        for (component, reading) in readings {
            guard reading.isCharging != true, let level = reading.level else {
                clear(component)
                continue
            }

            if level >= warningResetLevel { warningLatched.remove(component) }
            if level >= criticalResetLevel { criticalLatched.remove(component) }

            defer { lastLevels[component] = level }
            guard let previous = lastLevels[component] else { continue }

            if previous > criticalThreshold, level <= criticalThreshold,
               !criticalLatched.contains(component) {
                criticalLatched.insert(component)
                warningLatched.insert(component)
                crossed.append((BatteryAlertReading(component: component, level: level), .critical))
            } else if previous > warningThreshold, level <= warningThreshold,
                      !warningLatched.contains(component) {
                warningLatched.insert(component)
                crossed.append((BatteryAlertReading(component: component, level: level), .warning))
            }
        }

        guard !crossed.isEmpty else { return nil }
        let severity: BatteryAlertSeverity = crossed.contains { $0.1 == .critical }
            ? .critical : .warning
        return BatteryAlert(severity: severity, readings: crossed.map(\.0))
    }

    private func effectiveReadings(from state: BatteryState)
        -> [(BatteryComponent, BatteryReading)] {
        var result: [(BatteryComponent, BatteryReading)] = []
        let hasPerBudLevel = state.left?.level != nil || state.right?.level != nil

        if let left = state.left { result.append((.left, left)) }
        if let right = state.right { result.append((.right, right)) }
        if let enclosure = state.enclosure { result.append((.enclosure, enclosure)) }
        if !hasPerBudLevel, let combined = state.combined {
            result.append((.combined, combined))
        }
        return result
    }

    private mutating func clear(_ component: BatteryComponent) {
        lastLevels.removeValue(forKey: component)
        warningLatched.remove(component)
        criticalLatched.remove(component)
    }
}

private extension BatteryComponent {
    static let allCases: [BatteryComponent] = [.left, .right, .enclosure, .combined]
}
