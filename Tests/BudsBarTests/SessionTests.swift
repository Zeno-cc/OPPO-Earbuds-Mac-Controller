import XCTest
@testable import BudsCore

final class SessionTests: XCTestCase {
    private final class FakeTransport: ControlTransport {
        var eventHandler: ((ControlTransportEvent) -> Void)?
        var isOpen = false
        var sent: [[UInt8]] = []
        var openCount = 0
        var closeCount = 0
        var sendSucceeds = true

        func open() {
            openCount += 1
            isOpen = true
            eventHandler?(.opened)
        }

        func close() {
            closeCount += 1
            isOpen = false
            eventHandler?(.closed)
        }

        func send(_ bytes: [UInt8]) -> Bool {
            guard isOpen, sendSucceeds else { return false }
            sent.append(bytes)
            return true
        }

        func receive(_ hex: String) {
            let bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            eventHandler?(.bytes(bytes))
        }

        func disconnectUnexpectedly() {
            isOpen = false
            eventHandler?(.closed)
        }
    }

    func testOpenSendsOneHandshakeAndBecomesReady() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)

        session.open(intent: .connected)

        XCTAssertEqual(transport.openCount, 1)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(Array(transport.sent[0][4...5]), [0x00, 0x01])
        XCTAssertEqual(session.connectionState, .ready)
        XCTAssertEqual(session.intent, .connected)
    }

    func testIncomingFramesReduceIntoSessionState() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        transport.receive("aa 0f 00 00 04 02 4f 08 00 01 03 01 e4 02 64 03 1e")
        transport.receive("aa 0c 00 00 04 02 60 05 00 03 01 01 20 00")

        XCTAssertNil(session.state.battery.left)
        XCTAssertEqual(session.state.battery.right, 100)
        XCTAssertEqual(session.state.battery.enclosure, 30)
        XCTAssertEqual(session.state.mode, .noiseCancellation)
        XCTAssertEqual(session.state.ancLevel, .moderate)
    }

    func testSetWaitsForReportBeforeChangingRealState() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()
        let handshakeCount = transport.sent.count

        XCTAssertTrue(session.set(mode: .transparency))
        XCTAssertNil(session.state.mode)
        XCTAssertEqual(session.state.pendingMode, .transparency)
        XCTAssertEqual(transport.sent.count, handshakeCount + 1)
        XCTAssertEqual(transport.sent.last?.last, 0x04)

        transport.receive("aa 0c 00 00 04 02 67 05 00 03 01 01 00 01")
        XCTAssertEqual(session.state.mode, .transparency)
        XCTAssertNil(session.state.pendingMode)
    }

    func testUnknownProfileReadsBatteryButRejectsWrites() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .unknown, transport: transport)
        session.open()
        let handshakeCount = transport.sent.count

        XCTAssertFalse(session.set(mode: .off))
        XCTAssertEqual(transport.sent.count, handshakeCount)

        transport.receive("aa 0d 00 00 04 02 24 06 00 01 02 01 64 02 64")
        XCTAssertEqual(session.state.battery.left, 100)
        XCTAssertEqual(session.state.battery.right, 100)
    }

    func testUserCloseRecordsIntentAndDoesNotReopen() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .t500Pro, transport: transport)
        session.open()

        session.close(intent: .disconnectedByUser)

        XCTAssertEqual(session.connectionState, .idle)
        XCTAssertEqual(session.intent, .disconnectedByUser)
        XCTAssertEqual(transport.closeCount, 1)
        XCTAssertEqual(transport.openCount, 1)
    }

    func testTransportFailureIsVisibleAndCanRetry() {
        let transport = FakeTransport()
        transport.sendSucceeds = false
        let session = EarbudsSession(profile: .t500Pro, transport: transport)

        session.open()
        XCTAssertEqual(session.connectionState, .failed(.handshakeFailed))

        transport.sendSucceeds = true
        session.open()
        XCTAssertEqual(session.connectionState, .ready)
        XCTAssertEqual(transport.openCount, 2)
    }

    func testUnexpectedCloseCanBeOpenedAgain() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .t500Pro, transport: transport)
        session.open()

        transport.disconnectUnexpectedly()
        XCTAssertEqual(session.connectionState, .idle)

        session.open(intent: .automatic)
        XCTAssertEqual(session.connectionState, .ready)
        XCTAssertEqual(transport.openCount, 2)
    }

    func testInitialStateSurvivesControlChannelRecreation() {
        let transport = FakeTransport()
        var initialState = EarbudsState()
        initialState.battery.enclosure = 80
        let session = EarbudsSession(
            profile: .encoAir5Pro,
            transport: transport,
            initialState: initialState)

        session.open()

        XCTAssertEqual(session.state.battery.enclosure, 80)
    }
}
