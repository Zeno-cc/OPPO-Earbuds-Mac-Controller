import BudsCore
import XCTest
@testable import BudsBar

final class RFCOMMLifecycleTests: XCTestCase {
    private final class Channel {}
    private var lifecycle = RFCOMMLifecycle<Channel>()
    private var events: [ControlTransportEvent] = []

    override func setUp() {
        super.setUp()
        lifecycle = RFCOMMLifecycle<Channel>()
        events = []
        lifecycle.eventHandler = { [weak self] in self?.events.append($0) }
    }

    private func connect() -> Channel {
        let channel = Channel()
        let generation = lifecycle.beginOpen()!
        lifecycle.attach(channel, generation: generation)
        lifecycle.opened(channel, error: nil)
        return channel
    }

    func testCancelledDiscoveryCannotOpenOrFailReplacement() {
        let old = lifecycle.beginOpen()!
        _ = lifecycle.close()
        let current = lifecycle.beginOpen()!
        XCTAssertFalse(lifecycle.acceptsDiscovery(old))
        lifecycle.discoveryFailed("old SDP failure", generation: old)
        lifecycle.attach(Channel(), generation: old)
        XCTAssertTrue(lifecycle.acceptsDiscovery(current))
        XCTAssertNil(lifecycle.channel)
        XCTAssertNil(lifecycle.beginOpen())
        XCTAssertTrue(events.isEmpty)
    }

    func testOldGenerationCannotDeliverCallbacksForReusedChannel() {
        let channel = connect()
        let old = lifecycle.generation
        _ = lifecycle.close()
        let current = lifecycle.beginOpen()!
        lifecycle.attach(channel, generation: current)
        events = []
        lifecycle.deliver(generation: old) { lifecycle.opened(channel, error: nil) }
        XCTAssertFalse(lifecycle.isOpen)
        lifecycle.deliver(generation: current) { lifecycle.opened(channel, error: nil) }
        events = []
        lifecycle.deliver(generation: old) {
            lifecycle.received([1], from: channel)
            lifecycle.writeCompleted(channel, error: "old write error")
            lifecycle.closed(channel)
        }
        XCTAssertTrue(lifecycle.isOpen)
        XCTAssertTrue(events.isEmpty)
        lifecycle.deliver(generation: current) { lifecycle.received([2], from: channel) }
        XCTAssertEqual(events, [.bytes([2])])
    }

    func testCurrentDiscoveryFailureAllowsRetry() {
        let generation = lifecycle.beginOpen()!
        lifecycle.discoveryFailed("missing service", generation: generation)
        XCTAssertEqual(events, [.failed(TransportError("missing service"))])
        XCTAssertNotNil(lifecycle.beginOpen())
    }

    func testOldOpenSuccessAndFailureCannotReplaceNewChannel() {
        let old = connect()
        _ = lifecycle.close()
        let current = connect()
        events = []
        lifecycle.opened(old, error: nil)
        lifecycle.opened(old, error: "old open error")
        XCTAssertTrue(lifecycle.channel === current)
        XCTAssertTrue(lifecycle.isOpen)
        XCTAssertTrue(events.isEmpty)
    }

    func testOldCallbacksCannotFinishReplacementWhileItIsOpening() {
        let old = connect()
        _ = lifecycle.close()
        let current = Channel()
        lifecycle.attach(current, generation: lifecycle.beginOpen()!)
        events = []
        lifecycle.opened(old, error: "old failure")
        lifecycle.closed(old)
        lifecycle.received([1], from: old)
        lifecycle.writeCompleted(old, error: "old write error")
        XCTAssertFalse(lifecycle.isOpen)
        XCTAssertTrue(lifecycle.channel === current)
        XCTAssertTrue(events.isEmpty)
        lifecycle.opened(current, error: nil)
        XCTAssertTrue(lifecycle.isOpen)
        XCTAssertEqual(events, [.opened])
    }

    func testOldCloseDataAndWriteErrorCannotAffectNewChannel() {
        let old = connect()
        _ = lifecycle.close()
        let current = connect()
        events = []
        XCTAssertFalse(lifecycle.acceptsData(from: old))
        lifecycle.received([1], from: old)
        lifecycle.closed(old)
        lifecycle.writeCompleted(old, error: "old write error")
        XCTAssertTrue(lifecycle.channel === current)
        XCTAssertTrue(lifecycle.isOpen)
        XCTAssertTrue(events.isEmpty)
        lifecycle.received([2], from: current)
        XCTAssertEqual(events, [.bytes([2])])
    }

    func testCloseInvalidatesBeforeSynchronousClosedCallback() {
        let channel = connect()
        events = []
        XCTAssertTrue(lifecycle.close() === channel)
        lifecycle.closed(channel)
        lifecycle.opened(channel, error: nil)
        XCTAssertFalse(lifecycle.isOpen)
        XCTAssertNil(lifecycle.channel)
        XCTAssertTrue(events.isEmpty)
    }

    func testCurrentOpenFailureAndRemoteCloseAllowRetry() {
        let channel = Channel()
        lifecycle.attach(channel, generation: lifecycle.beginOpen()!)
        lifecycle.opened(channel, error: "open error")
        XCTAssertFalse(lifecycle.isOpen)
        XCTAssertEqual(events, [.failed(TransportError("open error"))])
        let current = connect()
        events = []
        lifecycle.closed(current)
        XCTAssertEqual(events, [.closed])
        XCTAssertFalse(lifecycle.isOpen)
        XCTAssertNotNil(lifecycle.beginOpen())
    }

    func testBufferedWriteSuccessIsNotStateConfirmationAndCompletionErrorSurfaces() {
        let channel = connect()
        events = []
        XCTAssertTrue(lifecycle.send([1], mtu: 127) { _ in nil })
        lifecycle.writeCompleted(channel, error: nil)
        XCTAssertTrue(events.isEmpty)
        lifecycle.writeCompleted(channel, error: "completion error")
        XCTAssertEqual(events, [.failed(TransportError("completion error"))])
    }

    func testInvalidLengthsNeverReachWriteAndBoundaryRemainsUsable() {
        _ = connect()
        for (count, mtu) in [(0, 127), (128, 127), (65_536, 100_000), (1, 0)] {
            var writes = 0
            XCTAssertFalse(lifecycle.send(Array(repeating: 1, count: count), mtu: mtu) { _ in
                writes += 1
                return nil
            })
            XCTAssertEqual(writes, 0)
        }
        XCTAssertEqual(events.filter { if case .failed = $0 { return true }; return false }.count, 4)
        XCTAssertTrue(lifecycle.send(Array(repeating: 1, count: 127), mtu: 127) { _ in nil })
        XCTAssertTrue(lifecycle.send(Array(repeating: 1, count: 65_535), mtu: 65_535) { _ in nil })
    }

    func testImmediateWriteErrorAndClosedSend() {
        _ = connect()
        events = []
        XCTAssertFalse(lifecycle.send([1], mtu: 127) { _ in "buffer error" })
        XCTAssertEqual(events, [.failed(TransportError("buffer error"))])
        _ = lifecycle.close()
        XCTAssertFalse(lifecycle.send([1], mtu: 127) { _ in
            XCTFail("closed channel must not write")
            return nil
        })
    }

    func testTraceDefaultsToMetadataAndRawRequiresExplicitOptIn() {
        let bytes = Array("Phone AA:BB:CC:DD:EE:FF".utf8)
        let metadata = "2026-09-06T03:00:00Z generation=7 direction=RX length=\(bytes.count)"
        XCTAssertEqual(RFCOMMTraceFormatter.line(
            bytes, timestamp: "2026-09-06T03:00:00Z", generation: 7,
            direction: "RX", includeRaw: false), metadata)
        XCTAssertEqual(RFCOMMTraceFormatter.line(
            bytes, timestamp: "2026-09-06T03:00:00Z", generation: 7,
            direction: "RX", includeRaw: true), "\(metadata) hex=\(BudsProtocol.hex(bytes))")
    }
}
