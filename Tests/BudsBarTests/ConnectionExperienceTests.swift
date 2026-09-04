import XCTest
@testable import BudsBar

final class ConnectionExperienceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testHUDPresentationLifecycleExpandsThenCollapsesBeforeDismissal() {
        var lifecycle = HUDPresentationLifecycle()

        XCTAssertEqual(lifecycle.start(), .compact)
        XCTAssertEqual(lifecycle.advance(), .expanding(.container))
        XCTAssertEqual(lifecycle.advance(), .expanding(.battery))
        XCTAssertEqual(lifecycle.advance(), .expanding(.complete))
        XCTAssertEqual(lifecycle.advance(), .expanded)
        XCTAssertEqual(lifecycle.advance(), .collapsing(.content))
        XCTAssertEqual(lifecycle.advance(), .collapsing(.container))
        XCTAssertEqual(lifecycle.advance(), .dismissing)
        XCTAssertEqual(lifecycle.advance(), .hidden)
    }

    func testHUDPresentationStateStaggersSecondaryContent() {
        XCTAssertFalse(HUDPresentationState.compact.showsBattery)
        XCTAssertFalse(HUDPresentationState.expanding(.container).showsBattery)
        XCTAssertTrue(HUDPresentationState.expanding(.battery).showsBattery)
        XCTAssertFalse(HUDPresentationState.expanding(.battery).showsMode)
        XCTAssertTrue(HUDPresentationState.expanding(.complete).showsMode)
        XCTAssertFalse(HUDPresentationState.collapsing(.content).showsBattery)
        XCTAssertTrue(HUDPresentationState.collapsing(.content).usesExpandedGeometry)
        XCTAssertFalse(HUDPresentationState.collapsing(.container).usesExpandedGeometry)
    }

    func testHUDLayoutUsesCompactAndEventSpecificExpandedSizes() {
        XCTAssertEqual(HUDPanelLayout.compactSize.width, 268)
        XCTAssertEqual(HUDPanelLayout.compactSize.height, 64)

        let connected = HUDPanelLayout.expandedSize(
            event: .connected,
            hasBattery: true,
            hasMode: true)
        XCTAssertEqual(connected.width, 350)
        XCTAssertEqual(connected.height, 120)

        let disconnected = HUDPanelLayout.expandedSize(
            event: .unexpectedDisconnected,
            hasBattery: false,
            hasMode: false)
        XCTAssertEqual(disconnected.width, 330)
        XCTAssertEqual(disconnected.height, 92)
    }

    func testHUDMotionTimelineUsesAReadableLongerDwell() {
        XCTAssertEqual(HUDMotionTokens.compactEnter, 0.22, accuracy: 0.001)
        XCTAssertEqual(HUDMotionTokens.expand, 0.42, accuracy: 0.001)
        XCTAssertEqual(HUDMotionTokens.expandedHold, 2.65, accuracy: 0.001)
        XCTAssertEqual(HUDMotionTokens.totalPresentationDuration, 4.27, accuracy: 0.001)
    }

    func testHUDExpansionSpringFeelsSoftWithoutPronouncedBounce() {
        XCTAssertEqual(HUDMotionTokens.springResponse, 0.48, accuracy: 0.001)
        XCTAssertEqual(HUDMotionTokens.springDamping, 0.80, accuracy: 0.001)
        XCTAssertEqual(HUDMotionTokens.hoverExitHold, 1.60, accuracy: 0.001)
    }

    func testFirstObservationOnlyEstablishesBaseline() {
        var experience = ConnectionExperience()

        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start),
            [.establishBaseline])
        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(0.1)),
            [])
    }

    func testFreshConnectAfterDisconnectedBaseline() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: false), at: start)

        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(1)),
            [.present(.connected)])
    }

    func testManualDisconnectIsSuppressedAndNextConnectIsFresh() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: true), at: start)

        XCTAssertEqual(
            experience.observe(
                .init(isConnected: false, suppressUnexpectedDisconnect: true),
                at: start.addingTimeInterval(1)),
            [])
        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(2)),
            [.present(.connected)])
    }

    func testManualDisconnectResetsConnectedHUDDeduplication() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: false), at: start)
        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(1)),
            [.present(.connected)])

        XCTAssertEqual(
            experience.observe(
                .init(isConnected: false, suppressUnexpectedDisconnect: true),
                at: start.addingTimeInterval(2)),
            [])
        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(3)),
            [.present(.connected)])
    }

    func testUnexpectedDisconnectSchedulesAfterDebounce() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: true), at: start)

        XCTAssertEqual(
            experience.observe(.init(isConnected: false), at: start.addingTimeInterval(1)),
            [.scheduleUnexpectedDisconnect(after: 0.65)])
        XCTAssertEqual(
            experience.confirmUnexpectedDisconnect(at: start.addingTimeInterval(1.65)),
            .present(.unexpectedDisconnected))
    }

    func testRapidReconnectCancelsDisconnectAndPresentsOneReconnect() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: true), at: start)
        _ = experience.observe(.init(isConnected: false), at: start.addingTimeInterval(1))

        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(1.4)),
            [.cancelUnexpectedDisconnect, .present(.reconnected)])
        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(1.5)),
            [])
    }

    func testReconnectAfterConfirmedUnexpectedDisconnect() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: true), at: start)
        _ = experience.observe(.init(isConnected: false), at: start.addingTimeInterval(1))
        _ = experience.confirmUnexpectedDisconnect(at: start.addingTimeInterval(1.65))

        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(3)),
            [.present(.reconnected)])
    }

    func testDuplicatePresentationWithinFiveSecondsIsSuppressed() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: false), at: start)
        _ = experience.observe(.init(isConnected: true), at: start.addingTimeInterval(1))
        experience.rebaseline(.init(isConnected: false))

        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(3)),
            [])
        experience.rebaseline(.init(isConnected: false))
        XCTAssertEqual(
            experience.observe(.init(isConnected: true), at: start.addingTimeInterval(7)),
            [.present(.connected)])
    }

    func testWakeRebaselineCancelsPendingAndSuppressesTransientState() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: true), at: start)
        _ = experience.observe(.init(isConnected: false), at: start.addingTimeInterval(1))

        XCTAssertEqual(
            experience.rebaseline(.init(isConnected: false)),
            [.cancelUnexpectedDisconnect])
        XCTAssertEqual(
            experience.confirmUnexpectedDisconnect(at: start.addingTimeInterval(2)),
            nil)
    }
}
