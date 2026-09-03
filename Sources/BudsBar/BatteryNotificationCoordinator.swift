import BudsCore
import Foundation
import UserNotifications

final class BatteryNotificationCoordinator {
    private let center: UNUserNotificationCenter
    private var policy = BatteryNotificationPolicy()
    private(set) var isEnabled = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        center.requestAuthorization(options: [.alert, .sound], completionHandler: completion)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        policy.reset()
    }

    func reset() {
        policy.reset()
    }

    func update(deviceName: String,
                state: BatteryState,
                suppressing suppressedComponents: Set<BatteryComponent> = []) {
        guard isEnabled,
              let alert = policy.evaluate(state, suppressing: suppressedComponents)
        else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.severity == .critical
            ? "\(deviceName) 电量严重不足"
            : "\(deviceName) 电量较低"
        content.body = alert.readings.map(Self.description).joined(separator: "，")
        content.sound = .default

        center.add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil))
    }

    private static func description(_ reading: BatteryAlertReading) -> String {
        let label: String
        switch reading.component {
        case .left: label = "左耳"
        case .right: label = "右耳"
        case .enclosure: label = "充电盒"
        case .combined: label = "耳机"
        }
        return "\(label) \(reading.level)%"
    }
}
