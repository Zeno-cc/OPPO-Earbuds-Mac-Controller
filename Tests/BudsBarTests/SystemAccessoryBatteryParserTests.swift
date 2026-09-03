import XCTest
@testable import BudsBar

final class SystemAccessoryBatteryParserTests: XCTestCase {
    func testParsesObservedPmsetAccessoryOutput() {
        let output = """
        Currently drawing from 'AC Power'
         -OPPO Enco Air5 Pro (id=10949541)\t100%; charged present: true
        """

        XCTAssertEqual(
            SystemAccessoryBatteryParser.percentage(
                in: output, matching: "OPPO Enco Air5 Pro"),
            100)
    }

    func testSelectsOnlyTheRequestedAccessory() {
        let output = """
         -Keyboard (id=1)\t65%; discharging present: true
         -OPPO Enco Air5 Pro (id=2)\t80%; discharging present: true
        """

        XCTAssertEqual(
            SystemAccessoryBatteryParser.percentage(
                in: output, matching: "oppo enco air5 pro"),
            80)
        XCTAssertNil(
            SystemAccessoryBatteryParser.percentage(
                in: output, matching: "Other Earbuds"))
    }

    func testRejectsSleepingZeroValue() {
        let output = " -OPPO Enco Air5 Pro (id=2)\t0%; present: false"
        XCTAssertNil(
            SystemAccessoryBatteryParser.percentage(
                in: output, matching: "OPPO Enco Air5 Pro"))
    }
}
