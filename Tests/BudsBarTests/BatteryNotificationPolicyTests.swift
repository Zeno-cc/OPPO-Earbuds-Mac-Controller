import XCTest
@testable import BudsCore

final class BatteryNotificationPolicyTests: XCTestCase {
    func testWarnsOnlyWhenLevelCrossesTwentyPercent() {
        var policy = BatteryNotificationPolicy()

        XCTAssertNil(policy.evaluate(.init(left: .init(level: 25))))
        XCTAssertEqual(
            policy.evaluate(.init(left: .init(level: 19))),
            BatteryAlert(severity: .warning,
                         readings: [.init(component: .left, level: 19)]))
        XCTAssertNil(policy.evaluate(.init(left: .init(level: 18))))
    }

    func testCriticalAlertTriggersOnlyWhenLevelCrossesTenPercent() {
        var policy = BatteryNotificationPolicy()

        XCTAssertNil(policy.evaluate(.init(right: .init(level: 11))))
        XCTAssertEqual(policy.evaluate(.init(right: .init(level: 9)))?.severity, .critical)
        XCTAssertNil(policy.evaluate(.init(right: .init(level: 8))))
    }

    func testHysteresisPreventsThresholdJitterFromRepeating() {
        var policy = BatteryNotificationPolicy()

        XCTAssertNil(policy.evaluate(.init(left: .init(level: 25))))
        XCTAssertNotNil(policy.evaluate(.init(left: .init(level: 19))))
        XCTAssertNil(policy.evaluate(.init(left: .init(level: 21))))
        XCTAssertNil(policy.evaluate(.init(left: .init(level: 19))))
        XCTAssertNil(policy.evaluate(.init(left: .init(level: 25))))
        XCTAssertNotNil(policy.evaluate(.init(left: .init(level: 19))))
    }

    func testChargingReadingSuppressesAndResetsAlertState() {
        var policy = BatteryNotificationPolicy()

        XCTAssertNil(policy.evaluate(.init(left: .init(level: 25))))
        XCTAssertNotNil(policy.evaluate(.init(left: .init(level: 19))))
        XCTAssertNil(policy.evaluate(.init(left: .init(level: 19, isCharging: true))))
        XCTAssertNil(policy.evaluate(.init(left: .init(level: 25))))
        XCTAssertNotNil(policy.evaluate(.init(left: .init(level: 19))))
    }

    func testPlacementSuppressionDoesNotPretendBatteryIsCharging() {
        var policy = BatteryNotificationPolicy()
        let high = BatteryState(left: .init(level: 25, isCharging: false))
        let low = BatteryState(left: .init(level: 19, isCharging: false))

        XCTAssertNil(policy.evaluate(high))
        XCTAssertNil(policy.evaluate(low, suppressing: [.left]))
        XCTAssertNil(policy.evaluate(low))
    }

    func testSimultaneousBudCrossingsProduceOneMergedAlert() {
        var policy = BatteryNotificationPolicy()

        XCTAssertNil(policy.evaluate(.init(
            left: .init(level: 30), right: .init(level: 30))))
        XCTAssertEqual(
            policy.evaluate(.init(left: .init(level: 19), right: .init(level: 9))),
            BatteryAlert(
                severity: .critical,
                readings: [
                    .init(component: .left, level: 19),
                    .init(component: .right, level: 9),
                ]))
    }

    func testCombinedReadingIsIgnoredWhenPerBudLevelsExist() {
        var policy = BatteryNotificationPolicy()

        XCTAssertNil(policy.evaluate(.init(
            left: .init(level: 30), combined: .init(level: 30))))
        let alert = policy.evaluate(.init(
            left: .init(level: 19), combined: .init(level: 9)))

        XCTAssertEqual(alert?.readings, [.init(component: .left, level: 19)])
    }
}
