import XCTest
@testable import BudsCore

final class CommandQueueTests: XCTestCase {
    private final class FakeTransport: ControlTransport {
        var eventHandler: ((ControlTransportEvent) -> Void)?
        var isOpen = true
        var sent: [[UInt8]] = []
        var sendSucceeds = true

        func open() {}
        func close() { isOpen = false }

        func send(_ bytes: [UInt8]) -> Bool {
            guard isOpen, sendSucceeds else { return false }
            sent.append(bytes)
            return true
        }
    }

    private final class ManualScheduler {
        private struct Job {
            let delay: TimeInterval
            let action: () -> Void
        }

        private var jobs: [Job] = []

        func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
            jobs.append(Job(delay: delay, action: action))
        }

        func runNext() {
            guard let index = jobs.indices.min(by: { jobs[$0].delay < jobs[$1].delay })
            else { return }
            jobs.remove(at: index).action()
        }
    }

    private func frame(_ hex: String) -> BudsProtocol.Frame {
        var bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        return BudsProtocol.drainFrames(from: &bytes)[0]
    }

    private func command(_ marker: UInt8,
                         matching opcode: UInt16 = 0x0681,
                         retryLimit: Int = 1) -> PendingCommand {
        PendingCommand(
            packet: [marker], sequence: marker, timeout: 1, retryLimit: retryLimit,
            responseMatcher: { $0.opcode == opcode })
    }

    func testQueriesAreSerialAndPacedAfterResponse() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(
            transport: transport, pacing: 0.2, scheduler: scheduler.schedule)
        var completed: [UInt8] = []

        queue.enqueue(command(0x01)) { _ in completed.append(0x01) }
        queue.enqueue(command(0x02)) { _ in completed.append(0x02) }

        XCTAssertEqual(transport.sent, [[0x01]])
        XCTAssertTrue(queue.receive(frame("aa 07 00 00 06 81 10 00 00")))
        XCTAssertEqual(completed, [0x01])
        XCTAssertEqual(transport.sent, [[0x01]])

        scheduler.runNext()
        XCTAssertEqual(transport.sent, [[0x01], [0x02]])
    }

    func testCompletionCannotEnqueueAroundPacingGate() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(
            transport: transport, pacing: 0.2, scheduler: scheduler.schedule)

        queue.enqueue(command(0x01)) { _ in
            queue.enqueue(self.command(0x02)) { _ in }
        }
        XCTAssertTrue(queue.receive(frame("aa 07 00 00 06 81 10 00 00")))

        XCTAssertEqual(transport.sent, [[0x01]])
        scheduler.runNext()
        XCTAssertEqual(transport.sent, [[0x01], [0x02]])
    }

    func testQueryTimesOutAfterOneRetry() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(
            transport: transport, pacing: 0.2, scheduler: scheduler.schedule)
        var failure: QueryCommandFailure?

        queue.enqueue(command(0x01)) { result in
            if case .failure(let reason) = result { failure = reason }
        }
        scheduler.runNext() // first timeout
        scheduler.runNext() // paced retry
        scheduler.runNext() // second timeout

        XCTAssertEqual(transport.sent, [[0x01], [0x01]])
        XCTAssertEqual(failure, .timedOut)
        XCTAssertFalse(queue.hasPendingQuery)
    }

    func testNonMatchingResponseLeavesQueryPending() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(transport: transport, scheduler: scheduler.schedule)
        var completed = false

        queue.enqueue(command(0x01)) { _ in completed = true }

        XCTAssertFalse(queue.receive(frame("aa 07 00 00 04 02 10 00 00")))
        XCTAssertFalse(completed)
        XCTAssertTrue(queue.hasPendingQuery)
    }

    func testSetCommandIsSentOnceWithoutSchedulingRetry() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(transport: transport, scheduler: scheduler.schedule)

        XCTAssertTrue(queue.setNoiseMode(.transparency, level: nil, profile: .encoAir5Pro))
        scheduler.runNext()

        XCTAssertEqual(transport.sent.count, 1)
    }

    func testAir5SoundSetCommandsAreSentOnce() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(transport: transport, scheduler: scheduler.schedule)

        XCTAssertTrue(queue.setEqualizer(.bass, profile: .encoAir5Pro))
        XCTAssertTrue(queue.setGameMode(false, profile: .encoAir5Pro))
        scheduler.runNext()

        XCTAssertEqual(transport.sent, [
            [0xaa, 0x08, 0x00, 0x00, 0x06, 0x04, 0x01, 0x01, 0x00, 0x01],
            [0xaa, 0x09, 0x00, 0x00, 0x03, 0x04, 0x02, 0x02, 0x00, 0x06, 0x00],
        ])
    }

    func testSendFailureDoesNotRetry() {
        let transport = FakeTransport()
        transport.sendSucceeds = false
        let scheduler = ManualScheduler()
        let queue = CommandQueue(transport: transport, scheduler: scheduler.schedule)
        var failure: QueryCommandFailure?

        queue.enqueue(command(0x01)) { result in
            if case .failure(let reason) = result { failure = reason }
        }

        XCTAssertEqual(failure, .sendFailed)
        XCTAssertFalse(queue.hasPendingQuery)
    }

    func testBatteryQueryUsesHandshakeSequenceAndMatchesResponseSequence() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(transport: transport, scheduler: scheduler.schedule)
        var completed = false

        XCTAssertTrue(queue.sendHello())
        XCTAssertTrue(queue.enqueueBatteryQuery(profile: .encoAir5Pro) { result in
            if case .success = result { completed = true }
        })
        XCTAssertEqual(
            transport.sent,
            [[0xaa, 0x07, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00],
             [0xaa, 0x07, 0x00, 0x00, 0x06, 0x01, 0x02, 0x00, 0x00]])

        XCTAssertFalse(queue.receive(frame("aa 0d 00 00 06 81 03 06 00 00 02 01 64 02 64")))
        XCTAssertFalse(completed)
        XCTAssertTrue(queue.receive(frame("aa 0d 00 00 06 81 02 06 00 00 02 01 64 02 64")))
        XCTAssertTrue(completed)
    }

    func testAir5SoundQueriesUseSharedSequenceAndMatchTheirResponses() {
        let transport = FakeTransport()
        let scheduler = ManualScheduler()
        let queue = CommandQueue(
            transport: transport, pacing: 0.2, scheduler: scheduler.schedule)
        var equalizerCompleted = false
        var gameCompleted = false

        XCTAssertTrue(queue.sendHello())
        XCTAssertTrue(queue.enqueueEqualizerQuery(profile: .encoAir5Pro) { result in
            if case .success = result { equalizerCompleted = true }
        })
        XCTAssertTrue(queue.enqueueGameModeQuery(profile: .encoAir5Pro) { result in
            if case .success = result { gameCompleted = true }
        })

        XCTAssertEqual(transport.sent.last,
                       [0xaa, 0x07, 0x00, 0x00, 0x0f, 0x01, 0x02, 0x00, 0x00])
        XCTAssertFalse(queue.receive(frame("aa 09 00 00 0f 81 03 02 00 00 00")))
        XCTAssertTrue(queue.receive(frame("aa 09 00 00 0f 81 02 02 00 00 00")))
        XCTAssertTrue(equalizerCompleted)

        scheduler.runNext()
        XCTAssertEqual(transport.sent.last,
                       [0xaa, 0x09, 0x00, 0x00, 0x0d, 0x01, 0x03, 0x02, 0x00, 0x01, 0x06])
        XCTAssertTrue(queue.receive(frame("aa 0b 00 00 0d 81 03 04 00 00 01 06 01")))
        XCTAssertTrue(gameCompleted)
    }
}
