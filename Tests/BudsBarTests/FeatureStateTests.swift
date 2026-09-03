import XCTest
@testable import BudsCore

final class FeatureStateTests: XCTestCase {
    func testFeatureStateDistinguishesAvailability() {
        XCTAssertNotEqual(FeatureState<Int>.unsupported, .unknown)
        XCTAssertNotEqual(FeatureState<Int>.unknown, .loading)
        XCTAssertEqual(FeatureState<Int>.ready(42), .ready(42))
        XCTAssertEqual(FeatureState<Int>.failed("读取失败"), .failed("读取失败"))
    }

    func testBatteryReadingKeepsZeroAndUnknownDistinct() {
        XCTAssertNotEqual(BatteryReading(), BatteryReading(level: 0))
        XCTAssertEqual(BatteryReading(level: 0, isCharging: false),
                       BatteryReading(level: 0, isCharging: false))
        XCTAssertNotEqual(BatteryReading(level: 0, isCharging: false),
                          BatteryReading(level: 0, isCharging: true))
    }
}
