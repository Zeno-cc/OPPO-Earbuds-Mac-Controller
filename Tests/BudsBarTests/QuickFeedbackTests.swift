import XCTest
import BudsCore
@testable import BudsBar

final class QuickFeedbackTests: XCTestCase {
    private final class Transport: ControlTransport {
        var eventHandler: ((ControlTransportEvent) -> Void)?
        var isOpen = false
        var sent: [[UInt8]] = []
        func open() { isOpen = true; eventHandler?(.opened) }
        func close() { isOpen = false; eventHandler?(.closed) }
        func send(_ bytes: [UInt8]) -> Bool { sent.append(bytes); return isOpen }
        func report(_ value: UInt8) {
            // Synthetic T500 mode notification, not a captured hardware fixture.
            eventHandler?(.bytes([0xaa, 0x0b, 0, 0, 4, 2, 0x48, 4, 0, 3, 1, 1, value]))
        }
        var writes: Int { sent.filter { $0.count > 5 && Array($0[4...5]) == [4, 4] }.count }
    }

    private final class Harness {
        let clock = TestClock()
        let transport = Transport()
        let session: EarbudsSession
        let buds: Buds
        var feedback: [QuickActionFeedback] = []
        var dismissals = 0
        init(mode: NoiseMode? = .noiseCancellation) {
            var state = EarbudsState()
            state.mode = mode
            session = EarbudsSession(profile: .t500Pro, transport: transport, initialState: state,
                                     now: { [clock] in clock.now }, scheduler: clock.schedule)
            session.open()
            buds = Buds(session: session, now: { [clock] in clock.now }, scheduleTimeout: { [clock] delay, item in
                clock.schedule(after: delay) { if !item.isCancelled { item.perform() } }
            })
            buds.onQuickActionFeedback = { [weak self] in self?.feedback.append($0) }
            buds.onQuickActionFeedbackDismissed = { [weak self] in self?.dismissals += 1 }
        }
    }

    func testRepeatedPressKeepsOriginalConfirmedReplyAndSendsOnce() {
        let h = Harness()
        XCTAssertTrue(h.buds.quickToggle())
        XCTAssertFalse(h.buds.quickToggle())
        XCTAssertFalse(h.buds.selectNoiseMode(.off))
        XCTAssertEqual(h.feedback, [.submitted])
        XCTAssertEqual(h.buds.mode, .noiseCancellation, "Submitting is not success")
        XCTAssertEqual(h.transport.writes, 1)
        h.transport.report(2)
        XCTAssertEqual(h.feedback, [.submitted, .confirmed(.transparency, nil)])
        h.transport.report(2)
        XCTAssertEqual(h.feedback.count, 2, "Repeated reports do not replay completion")
    }

    func testRepeatedPressDoesNotSwallowTimeoutOrTurnLateReportIntoSuccess() {
        let h = Harness()
        XCTAssertTrue(h.buds.quickToggle())
        h.clock.advance(by: 1.7)
        XCTAssertFalse(h.buds.quickToggle())
        XCTAssertEqual(h.feedback, [.submitted])
        h.clock.advance(by: 1.3)
        XCTAssertEqual(h.feedback.last, .failed("未能确认设置结果，请重新读取或手动重试"))
        h.transport.report(2)
        XCTAssertEqual(h.buds.mode, .transparency)
        XCTAssertEqual(h.feedback.count, 2)
    }

    func testUnknownModeRepeatedPressKeepsOriginalDeadline() {
        let h = Harness(mode: nil)
        XCTAssertTrue(h.buds.quickToggle())
        h.clock.advance(by: 1.5)
        XCTAssertTrue(h.buds.quickToggle())
        XCTAssertEqual(h.feedback, [.waitingForMode])
        h.clock.advance(by: 0.5)
        XCTAssertEqual(h.feedback, [.waitingForMode, .failed("未收到当前模式，未执行切换")])
        h.transport.report(2)
        XCTAssertEqual(h.transport.writes, 0, "Expired intent cannot execute later")
    }

    func testUnknownModeResolvesIntoOneWriteAndRealConfirmation() {
        let h = Harness(mode: nil)
        XCTAssertTrue(h.buds.quickToggle())
        h.transport.report(0x20)
        XCTAssertEqual(h.transport.writes, 1)
        XCTAssertEqual(h.feedback, [.waitingForMode, .submitted])
        h.transport.report(2)
        XCTAssertEqual(h.feedback.last, .confirmed(.transparency, nil))
        h.clock.advance(by: 3)
        XCTAssertEqual(h.feedback.count, 3)
    }

    func testPanelHandoffDropsReplyButDoesNotCancelSentWrite() {
        let h = Harness()
        XCTAssertTrue(h.buds.quickToggle())
        h.buds.cancelQuickIntent()
        XCTAssertEqual(h.dismissals, 1)
        XCTAssertTrue(h.session.state.operations[.noise]?.phase.isPending == true)
        h.transport.report(2)
        XCTAssertEqual(h.buds.mode, .transparency)
        XCTAssertEqual(h.feedback, [.submitted])
    }

    func testUnknownModeHandoffCancelsIntentAndScheduledFailure() {
        let h = Harness(mode: nil)
        XCTAssertTrue(h.buds.quickToggle())
        h.buds.cancelQuickIntent()
        h.clock.advance(by: 3)
        h.transport.report(0x20)
        XCTAssertEqual(h.transport.writes, 0)
        XCTAssertEqual(h.feedback, [.waitingForMode])
    }

    func testDisconnectReportsAcceptedOperationCancellationOnce() {
        let h = Harness()
        XCTAssertTrue(h.buds.quickToggle())
        h.transport.close()
        XCTAssertEqual(h.feedback.last, .failed("连接已中断，设置结果未确认"))
        h.clock.advance(by: 5)
        XCTAssertEqual(h.feedback.count, 2)
    }

    func testMenuSuccessStaysQuietAndFailureStillAppears() {
        let h = Harness()
        XCTAssertTrue(h.buds.quickToggleFromMenu())
        h.transport.report(2)
        XCTAssertTrue(h.feedback.isEmpty)
        h.clock.advance(by: 0.2)
        XCTAssertTrue(h.buds.quickToggleFromMenu())
        h.clock.advance(by: 3)
        XCTAssertEqual(h.feedback.count, 1)
        if case .failed = h.feedback.first {} else { XCTFail("Menu failure must be visible") }
    }

    func testHUDPendingHasNoReadingTimeoutAndOldTimerCannotHideNewPending() {
        var work: [DispatchWorkItem] = []
        let hud = QuickActionHUDController { _, item in work.append(item) }
        defer { hud.dismissImmediately() }
        hud.show(.waitingForMode)
        hud.show(.submitted)
        XCTAssertTrue(work.isEmpty)
        XCTAssertEqual(hud.visibleFeedback, .submitted)
        hud.show(.confirmed(.transparency, nil))
        let old = work[0]
        hud.show(.submitted)
        old.perform()
        XCTAssertEqual(hud.visibleFeedback, .submitted)
        XCTAssertTrue(hud.isShowing)
        hud.dismissImmediately()
        XCTAssertNil(hud.visibleFeedback)
    }
}
