import BudsCore
import XCTest
@testable import BudsBar

final class PresentationTests: XCTestCase {
    func testDeviceInformationRefreshFeedbackAdvancesOnlyForEnqueuedRequest() {
        XCTAssertEqual(
            DeviceInformationRefreshFeedback.nextTrigger(current: 2, didEnqueue: true),
            3)
        XCTAssertEqual(
            DeviceInformationRefreshFeedback.nextTrigger(current: 2, didEnqueue: false),
            2)
    }

    func testWhatsNewPanelCentersWithinVisibleScreenFrame() {
        let visibleFrame = NSRect(x: 1_440, y: 24, width: 1_920, height: 1_056)
        let panelSize = NSSize(width: 400, height: 360)

        let origin = WhatsNewPanelPositioning.centeredOrigin(
            panelSize: panelSize,
            visibleFrame: visibleFrame)

        XCTAssertEqual(origin.x, 2_200)
        XCTAssertEqual(origin.y, 372)
    }

    func testWhatsNewPresentationIsRequestedOnlyOncePerVersion() throws {
        let suite = "PresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(WhatsNewPresentationPolicy.requestIfNeeded(version: "1.3", settings: settings))
        XCTAssertTrue(settings.hasSeenWhatsNew(version: "1.3"))
        XCTAssertFalse(WhatsNewPresentationPolicy.requestIfNeeded(version: "1.3", settings: settings))
        XCTAssertTrue(WhatsNewPresentationPolicy.requestIfNeeded(version: "1.4", settings: settings))
    }

    func testDelightPreferencesHaveProductDefaultsAndPersistChanges() throws {
        let suite = "PresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.connectHUDEnabled)
        XCTAssertTrue(settings.reconnectHUDEnabled)
        XCTAssertTrue(settings.unexpectedDisconnectHUDEnabled)
        XCTAssertFalse(settings.menuBarBatteryEnabled)
        XCTAssertFalse(settings.hasSeenWhatsNew(version: "1.3"))

        settings.setConnectHUDEnabled(false)
        settings.setReconnectHUDEnabled(false)
        settings.setUnexpectedDisconnectHUDEnabled(false)
        settings.setMenuBarBatteryEnabled(true)
        settings.markWhatsNewSeen(version: "1.3")

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.connectHUDEnabled)
        XCTAssertFalse(restored.reconnectHUDEnabled)
        XCTAssertFalse(restored.unexpectedDisconnectHUDEnabled)
        XCTAssertTrue(restored.menuBarBatteryEnabled)
        XCTAssertTrue(restored.hasSeenWhatsNew(version: "1.3"))
    }

    func testBatteryPresentationPrefersVendorSlotsAndKeepsCase() {
        let presentation = BatteryPresentation(
            vendor: BatteryState(
                left: BatteryReading(level: 84, isCharging: false),
                enclosure: BatteryReading(level: 61, isCharging: true)),
            system: BatteryState(
                left: BatteryReading(level: 70),
                right: BatteryReading(level: 73),
                enclosure: BatteryReading(level: 55),
                combined: BatteryReading(level: 72)),
            placement: EarbudsPlacementState())

        XCTAssertEqual(presentation.items.map(\.kind), [.left, .right, .enclosure])
        XCTAssertEqual(presentation.items.map(\.reading.level), [84, 73, 61])
        XCTAssertEqual(presentation.menuBarPercentage, 73)
    }

    func testAggregateBatteryIsShownOnlyAsHeadphones() {
        let presentation = BatteryPresentation(
            vendor: BatteryState(),
            system: BatteryState(combined: BatteryReading(level: 80)),
            placement: EarbudsPlacementState())

        XCTAssertEqual(presentation.items.map(\.kind), [.combined])
        XCTAssertEqual(presentation.items.first?.label, "耳机")
        XCTAssertNil(presentation.menuBarPercentage)
    }

    func testMenuBarBatteryRequiresTwoIndependentValidReadings() {
        let oneSide = BatteryPresentation(
            vendor: BatteryState(left: BatteryReading(level: 42)),
            system: BatteryState(combined: BatteryReading(level: 90)),
            placement: EarbudsPlacementState())
        let invalidSide = BatteryPresentation(
            vendor: BatteryState(
                left: BatteryReading(level: 42),
                right: BatteryReading(level: 101)),
            system: BatteryState(),
            placement: EarbudsPlacementState())

        XCTAssertNil(oneSide.menuBarPercentage)
        XCTAssertNil(invalidSide.menuBarPercentage)
    }
}
