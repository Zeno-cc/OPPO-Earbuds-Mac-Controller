import XCTest
@testable import BudsBar
import BudsCore

final class ConnectionHUDValidityTests: XCTestCase {
    private final class Harness {
        let panel = ConnectionHUDPanelController()
        var busy = false
        var enabled = true
        var reconnectEnabled = true
        var details = true
        var snapshotRequests = 0
        lazy var coordinator = ConnectionHUDCoordinator(
            panelController: panel,
            snapshot: { [unowned self] event in
                snapshotRequests += 1
                return HUDSnapshot(
                    deviceName: "Same name on either device",
                    isConnected: event != .unexpectedDisconnected,
                    battery: BatteryPresentation(
                        vendor: BatteryState(), system: BatteryState(),
                        placement: EarbudsPlacementState()),
                    noiseControlText: details ? "ANC" : nil)
            },
            isEnabled: { [unowned self] event in
                enabled && (event != .reconnected || reconnectEnabled)
            },
            isSlotBusy: { [unowned self] in busy })

        func observe(_ connected: Bool, deliberate: Bool = false, identity: String? = nil) {
            coordinator.observe(.init(
                isConnected: connected, suppressUnexpectedDisconnect: deliberate,
                deviceIdentity: identity))
        }

        func close() {
            coordinator.stabilize(with: .init(isConnected: false))
        }
    }

    private func allowScheduledWork(after delay: TimeInterval) {
        let elapsed = expectation(description: "Scheduled HUD work has reached its deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: delay + 2)
    }

    func testReleasedSlotDoesNotPresentBeforeProcessingDeliberateDisconnect() {
        let h = Harness()
        defer { h.close() }
        h.busy = true
        h.observe(false)
        h.observe(true)
        h.busy = false
        h.observe(false, deliberate: true)
        h.coordinator.retryDeferredPresentation()
        XCTAssertNil(h.panel.visibleEvent)
        XCTAssertEqual(h.snapshotRequests, 0, "An obsolete event must not even request a snapshot")
    }

    func testReadinessWaitIsCancelledByDeliberateDisconnect() {
        let h = Harness()
        defer { h.close() }
        h.details = false
        h.observe(false)
        h.observe(true)
        h.observe(false, deliberate: true)
        allowScheduledWork(after: 1.1)
        XCTAssertNil(h.panel.visibleEvent)
    }

    func testReadinessCompletionRespectsBusySlotAndValidEventSurvives() {
        let h = Harness()
        defer { h.close() }
        h.details = false
        h.observe(false)
        h.observe(true)
        h.busy = true
        allowScheduledWork(after: 1.1)
        XCTAssertNil(h.panel.visibleEvent)
        h.details = true
        h.busy = false
        h.coordinator.retryDeferredPresentation()
        XCTAssertEqual(h.panel.visibleEvent, .connected)
    }

    func testReadinessCompletionRechecksPreferenceWithoutAnotherObservation() {
        let h = Harness()
        defer { h.close() }
        h.details = false
        h.observe(false)
        h.observe(true)
        h.enabled = false
        allowScheduledWork(after: 1.1)
        XCTAssertNil(h.panel.visibleEvent)
        h.enabled = true
        h.coordinator.retryDeferredPresentation()
        XCTAssertNil(h.panel.visibleEvent, "Discarded events must not replay when enabled")
    }

    func testValidReadinessTimeoutStillPresentsWithoutDetails() {
        let h = Harness()
        defer { h.close() }
        h.details = false
        h.observe(false)
        h.observe(true)
        allowScheduledWork(after: 1.1)
        XCTAssertEqual(h.panel.visibleEvent, .connected)
    }

    func testDetailsArrivalPresentsValidWaitingEvent() {
        let h = Harness()
        defer { h.close() }
        h.details = false
        h.observe(false)
        h.observe(true)
        XCTAssertNil(h.panel.visibleEvent)
        h.details = true
        h.observe(true)
        XCTAssertEqual(h.panel.visibleEvent, .connected)
    }

    func testReconnectRemovesDisconnectCardEvenWhenReconnectNotificationIsDisabled() {
        let h = Harness()
        defer { h.close() }
        h.observe(true)
        h.observe(false)
        allowScheduledWork(after: 0.75)
        XCTAssertEqual(h.panel.visibleEvent, .unexpectedDisconnected)
        h.reconnectEnabled = false
        h.observe(true)
        XCTAssertNil(h.panel.visibleEvent)
    }

    func testDisconnectImmediatelyInvalidatesConnectedCardBeforeDebounce() {
        let h = Harness()
        defer { h.close() }
        h.observe(false)
        h.observe(true)
        XCTAssertEqual(h.panel.visibleEvent, .connected)
        h.observe(false)
        XCTAssertNil(h.panel.visibleEvent)
    }

    func testPreferenceDiscardsSlotWaitAndVisibleCard() {
        let h = Harness()
        defer { h.close() }
        h.busy = true
        h.observe(false)
        h.observe(true)
        h.enabled = false
        h.coordinator.retryDeferredPresentation()
        h.busy = false
        h.enabled = true
        h.coordinator.retryDeferredPresentation()
        XCTAssertNil(h.panel.visibleEvent)
        h.observe(false, deliberate: true)
        h.observe(true)
        XCTAssertEqual(h.panel.visibleEvent, .connected)
        h.enabled = false
        h.observe(true)
        XCTAssertNil(h.panel.visibleEvent)
    }

    func testIdentitySwitchDiscardsSlotWaitAndResetsDeduplication() {
        let h = Harness()
        defer { h.close() }
        h.busy = true
        h.observe(false, identity: "A")
        h.observe(true, identity: "A")
        h.busy = false
        h.observe(false, identity: "B")
        h.coordinator.retryDeferredPresentation()
        XCTAssertNil(h.panel.visibleEvent)
        XCTAssertEqual(h.snapshotRequests, 0)
        h.observe(true, identity: "B")
        XCTAssertEqual(h.panel.visibleEvent, .connected)
        h.observe(true, identity: "C")
        XCTAssertNil(h.panel.visibleEvent, "Connected identity changes establish a silent baseline")
    }

    func testIdentitySwitchCancelsReadinessAndPendingDisconnect() {
        let h = Harness()
        defer { h.close() }
        h.details = false
        h.observe(false, identity: "A")
        h.observe(true, identity: "A")
        h.observe(true, identity: "B")
        allowScheduledWork(after: 1.1)
        XCTAssertNil(h.panel.visibleEvent)
        h.observe(false, identity: "B")
        h.observe(false, identity: "C")
        allowScheduledWork(after: 0.75)
        XCTAssertNil(h.panel.visibleEvent)
    }

    func testRebaselineClearsWaitingAndVisiblePresentation() {
        let h = Harness()
        defer { h.close() }
        h.busy = true
        h.observe(false)
        h.observe(true)
        h.coordinator.stabilize(with: .init(isConnected: false))
        h.busy = false
        h.coordinator.retryDeferredPresentation()
        XCTAssertNil(h.panel.visibleEvent)
        h.observe(true, identity: "B")
        h.observe(false, deliberate: true, identity: "B")
        h.observe(true, identity: "B")
        XCTAssertEqual(h.panel.visibleEvent, .connected)
        h.coordinator.stabilize(with: .init(isConnected: true, deviceIdentity: "B"))
        XCTAssertNil(h.panel.visibleEvent)
    }

    func testSuppressionArrivingDuringDebounceCancelsDisconnectAndReconnectSemantics() {
        var experience = ConnectionExperience()
        _ = experience.observe(.init(isConnected: true))
        _ = experience.observe(.init(isConnected: false))
        XCTAssertEqual(experience.observe(.init(
            isConnected: false, suppressUnexpectedDisconnect: true)), [.cancelUnexpectedDisconnect])
        XCTAssertNil(experience.confirmUnexpectedDisconnect())
        XCTAssertEqual(experience.observe(.init(isConnected: true)), [.present(.connected)])
    }
}
