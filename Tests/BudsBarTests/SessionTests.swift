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

        XCTAssertEqual(
            session.state.battery.left,
            BatteryReading(level: 100, isCharging: true))
        XCTAssertEqual(session.state.battery.right?.level, 100)
        XCTAssertEqual(session.state.battery.right?.isCharging, false)
        XCTAssertEqual(session.state.battery.enclosure?.level, 30)
        XCTAssertEqual(session.state.battery.enclosure?.isCharging, false)
        XCTAssertEqual(session.state.mode, .noiseCancellation)
        XCTAssertEqual(session.state.ancLevel, .moderate)
    }

    func testBatteryReportPreservesSlotsThatAreNotPresent() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        transport.receive("aa 0f 00 00 04 02 4f 08 00 01 03 01 50 02 46 03 3c")
        transport.receive("aa 0b 00 00 04 02 50 04 00 01 01 01 4b")

        XCTAssertEqual(session.state.battery.left?.level, 75)
        XCTAssertEqual(session.state.battery.right?.level, 70)
        XCTAssertEqual(session.state.battery.enclosure?.level, 60)
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

    func testEqualizerSetUsesReportAndQueryReadBack() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        XCTAssertTrue(session.set(equalizer: .vocals))
        XCTAssertEqual(session.state.pendingEqualizer, .vocals)
        XCTAssertEqual(
            transport.sent.suffix(2).map { $0 },
            [[0xaa, 0x08, 0x00, 0x00, 0x06, 0x04, 0x02, 0x01, 0x00, 0x02],
             [0xaa, 0x07, 0x00, 0x00, 0x0f, 0x01, 0x03, 0x00, 0x00]])

        transport.receive("aa 08 00 00 06 84 02 01 00 00")
        transport.receive("aa 08 00 00 04 05 f8 01 00 02")
        XCTAssertEqual(session.state.equalizerFeature, .ready(.vocals))
        XCTAssertNil(session.state.pendingEqualizer)

        transport.receive("aa 09 00 00 0f 81 03 02 00 00 02")
        XCTAssertEqual(session.state.equalizerFeature, .ready(.vocals))
    }

    func testGameModeSetWaitsForVerifiedQueryReadBack() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        XCTAssertTrue(session.set(gameMode: false))
        XCTAssertEqual(session.state.pendingGameMode, false)
        XCTAssertNotEqual(session.state.gameModeFeature, .ready(false))
        XCTAssertEqual(
            transport.sent.suffix(2).map { $0 },
            [[0xaa, 0x09, 0x00, 0x00, 0x03, 0x04, 0x02, 0x02, 0x00, 0x06, 0x00],
             [0xaa, 0x09, 0x00, 0x00, 0x0d, 0x01, 0x03, 0x02, 0x00, 0x01, 0x06]])

        transport.receive("aa 08 00 00 03 84 02 01 00 00")
        XCTAssertEqual(session.state.pendingGameMode, false)
        transport.receive("aa 0b 00 00 0d 81 03 04 00 00 01 06 00")

        XCTAssertEqual(session.state.gameModeFeature, .ready(false))
        XCTAssertNil(session.state.pendingGameMode)
    }

    func testMalformedGameModeReadBackClearsPendingFromReadyState() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        XCTAssertTrue(session.set(gameMode: true))
        transport.receive("aa 0b 00 00 0d 81 03 04 00 00 01 06 01")
        XCTAssertEqual(session.state.gameModeFeature, .ready(true))

        var observedPendingClear = false
        session.onStateChange = {
            observedPendingClear = session.state.pendingGameMode == nil
        }
        XCTAssertTrue(session.set(gameMode: false))
        XCTAssertEqual(session.state.pendingGameMode, false)
        let pendingCleared = expectation(description: "malformed read-back clears pending state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            transport.receive("aa 0b 00 00 0d 81 05 04 00 00 01 06 02")
            XCTAssertNil(session.state.pendingGameMode)
            XCTAssertEqual(session.state.gameModeFeature, .ready(true))
            XCTAssertTrue(observedPendingClear)
            pendingCleared.fulfill()
        }
        wait(for: [pendingCleared], timeout: 1)
    }

    func testBatteryRetryUsesVerifiedAir5QueryAndReducesResponse() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        session.retryBatterySync()

        XCTAssertEqual(
            transport.sent.last,
            [0xaa, 0x07, 0x00, 0x00, 0x06, 0x01, 0x02, 0x00, 0x00])
        XCTAssertEqual(session.state.batteryFeature, .loading)

        transport.receive("aa 0d 00 00 06 81 02 06 00 00 02 01 64 02 64")

        XCTAssertEqual(session.state.battery.left?.level, 100)
        XCTAssertEqual(session.state.battery.right?.level, 100)
        XCTAssertEqual(session.state.battery.left?.isCharging, false)
        XCTAssertEqual(session.state.battery.right?.isCharging, false)
        XCTAssertEqual(session.state.batteryFeature, .ready(session.state.battery))
    }

    func testActiveBatteryResponseReportsStowedBudChargingAndCaseLevel() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()
        session.retryBatterySync()

        transport.receive("aa 0f 00 00 06 81 02 08 00 00 03 01 64 02 e4 03 5a")

        XCTAssertEqual(session.state.battery.left?.level, 100)
        XCTAssertEqual(session.state.battery.left?.isCharging, false)
        XCTAssertEqual(session.state.battery.right?.level, 100)
        XCTAssertEqual(session.state.battery.right?.isCharging, true)
        XCTAssertEqual(session.state.battery.enclosure?.level, 90)
        XCTAssertEqual(session.state.battery.enclosure?.isCharging, false)
    }

    func testDeviceInformationQueryUpdatesFeatureState() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        XCTAssertTrue(session.retryDeviceInformationSync())
        XCTAssertEqual(
            transport.sent.last,
            [0xaa, 0x07, 0x00, 0x00, 0x06, 0x01, 0x02, 0x00, 0x00])
        XCTAssertEqual(session.state.deviceInformationFeature, .loading)

        transport.receive("aa 0d 00 00 06 81 02 06 00 00 02 01 64 02 64")
        let deviceQueryCompleted = expectation(description: "device information query completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertEqual(
                transport.sent.last,
                [0xaa, 0x07, 0x00, 0x00, 0x05, 0x01, 0x03, 0x00, 0x00])
            transport.receive(
                "aa 27 00 00 05 81 03 20 00 00 04 31 2c 32 2c 31 35 38 2c 32 2c 32 2c 31 35 38 2c 33 2c 31 2c 30 31 2c 33 2c 32 2c 31 30 35")
            deviceQueryCompleted.fulfill()
        }
        wait(for: [deviceQueryCompleted], timeout: 1)

        XCTAssertEqual(
            session.state.deviceInformationFeature,
            .ready(DeviceInformation(
                modelIdentifier: DeviceInformationField(
                    "OPPO Enco Air5 Pro", source: .profileMetadata),
                firmwareVersion: DeviceInformationField(
                    "158.158.105", source: .remoteQuery))))
    }

    func testImmediateBatteryRefreshDoesNotSkipDeviceInformationInitialSync() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        XCTAssertTrue(session.retryBatterySync())
        transport.receive("aa 0d 00 00 06 81 02 06 00 00 02 01 64 02 64")

        let deviceQuerySent = expectation(description: "device information query sent")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertEqual(
                transport.sent.last,
                [0xaa, 0x07, 0x00, 0x00, 0x05, 0x01, 0x03, 0x00, 0x00])
            deviceQuerySent.fulfill()
        }
        wait(for: [deviceQuerySent], timeout: 1)
    }

    func testMalformedDeviceInformationResponseIsVisible() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        XCTAssertTrue(session.retryDeviceInformationSync())
        transport.receive("aa 0d 00 00 06 81 02 06 00 00 02 01 64 02 64")
        let malformedHandled = expectation(description: "malformed device response handled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            transport.receive("aa 09 00 00 05 81 03 02 00 00 04")
            malformedHandled.fulfill()
        }
        wait(for: [malformedHandled], timeout: 1)

        XCTAssertEqual(
            session.state.deviceInformationFeature,
            .failed("设备信息响应格式异常"))
    }

    func testAir5ChargingBitTurnsOnAndOffWithoutChangingLevel() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        transport.receive("aa 0f 00 00 04 02 b1 08 00 01 03 01 e4 02 e4 03 da")

        XCTAssertEqual(
            session.state.battery.left,
            BatteryReading(level: 100, isCharging: true))
        XCTAssertEqual(
            session.state.battery.right,
            BatteryReading(level: 100, isCharging: true))
        XCTAssertEqual(
            session.state.battery.enclosure,
            BatteryReading(level: 90, isCharging: true))

        transport.receive("aa 0f 00 00 04 02 b2 08 00 01 03 01 e4 02 e4 03 5a")

        XCTAssertEqual(
            session.state.battery.enclosure,
            BatteryReading(level: 90, isCharging: false))
    }

    func testChargingReadingSurvivesFollowingPlacementReport() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        transport.receive("aa 0f 00 00 04 02 b7 08 00 01 03 01 e4 02 e4 03 da")
        transport.receive("aa 0f 00 00 04 02 bb 08 00 02 03 01 04 02 04 03 04")

        XCTAssertEqual(
            session.state.battery.left,
            BatteryReading(level: 100, isCharging: true))
        XCTAssertEqual(
            session.state.battery.right,
            BatteryReading(level: 100, isCharging: true))
    }

    func testAir5PlacementClearsOnlyTheBudPutInCase() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()
        transport.receive("aa 0d 00 00 04 02 60 06 00 01 02 01 64 02 64")

        transport.receive("aa 0f 00 00 04 02 63 08 00 02 03 01 04 02 05 03 04")

        XCTAssertEqual(session.state.placement.left, .inCase)
        XCTAssertEqual(session.state.placement.right, .inUse)
        XCTAssertNil(session.state.battery.left?.level)
        XCTAssertEqual(session.state.battery.right?.level, 100)
    }

    func testUnsupportedProfileDoesNotSendBatteryQuery() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .t500Pro, transport: transport)
        session.open()
        let handshakeCount = transport.sent.count

        session.retryBatterySync()
        XCTAssertFalse(session.retryDeviceInformationSync())

        XCTAssertEqual(transport.sent.count, handshakeCount)
        XCTAssertEqual(session.state.deviceInformationFeature, .unsupported)
        XCTAssertEqual(session.state.equalizerFeature, .unsupported)
        XCTAssertEqual(session.state.gameModeFeature, .unsupported)
        XCTAssertFalse(session.set(equalizer: .original))
        XCTAssertFalse(session.set(gameMode: true))
    }

    func testMalformedBatteryResponseCanBeRetried() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()

        XCTAssertTrue(session.retryBatterySync())
        transport.receive("aa 0b 00 00 06 81 02 04 00 00 02 01 64")
        XCTAssertEqual(session.state.batteryFeature, .failed("电量响应格式异常"))

        XCTAssertTrue(session.retryBatterySync())
        let deviceQueryCompleted = expectation(description: "queued device information query completed")
        let retrySent = expectation(description: "paced battery retry sent after initial sync")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertEqual(
                transport.sent.last,
                [0xaa, 0x07, 0x00, 0x00, 0x05, 0x01, 0x03, 0x00, 0x00])
            transport.receive(
                "aa 27 00 00 05 81 03 20 00 00 04 31 2c 32 2c 31 35 38 2c 32 2c 32 2c 31 35 38 2c 33 2c 31 2c 30 31 2c 33 2c 32 2c 31 30 35")
            deviceQueryCompleted.fulfill()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                XCTAssertEqual(
                    transport.sent.last,
                    [0xaa, 0x07, 0x00, 0x00, 0x0f, 0x01, 0x04, 0x00, 0x00])
                transport.receive("aa 09 00 00 0f 81 04 02 00 00 00")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    XCTAssertEqual(
                        transport.sent.last,
                        [0xaa, 0x09, 0x00, 0x00, 0x0d, 0x01,
                         0x05, 0x02, 0x00, 0x01, 0x06])
                    transport.receive("aa 0b 00 00 0d 81 05 04 00 00 01 06 01")

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        XCTAssertEqual(
                            transport.sent.last,
                            [0xaa, 0x07, 0x00, 0x00, 0x06, 0x01,
                             0x06, 0x00, 0x00])
                        transport.receive(
                            "aa 0d 00 00 06 81 06 06 00 00 02 01 64 02 64")
                        retrySent.fulfill()
                    }
                }
            }
        }
        wait(for: [deviceQueryCompleted, retrySent], timeout: 2)
        XCTAssertEqual(session.state.batteryFeature, .ready(session.state.battery))
    }

    func testUnknownProfileReadsBatteryButRejectsWrites() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .unknown, transport: transport)
        session.open()
        let handshakeCount = transport.sent.count

        XCTAssertFalse(session.set(mode: .off))
        XCTAssertEqual(transport.sent.count, handshakeCount)

        transport.receive("aa 0d 00 00 04 02 24 06 00 01 02 01 64 02 64")
        XCTAssertEqual(session.state.battery.left?.level, 100)
        XCTAssertEqual(session.state.battery.right?.level, 100)
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
        initialState.battery.enclosure = BatteryReading(level: 80)
        initialState.deviceInformationFeature = .ready(DeviceInformation(
            modelIdentifier: DeviceInformationField(
                "OPPO Enco Air5 Pro", source: .profileMetadata),
            firmwareVersion: DeviceInformationField(
                "158.158.105", source: .remoteQuery)))
        let session = EarbudsSession(
            profile: .encoAir5Pro,
            transport: transport,
            initialState: initialState)

        session.open()

        XCTAssertEqual(session.state.battery.enclosure?.level, 80)
        XCTAssertEqual(
            session.state.deviceInformationFeature,
            initialState.deviceInformationFeature)
    }

    func testUnsolicitedReportUpdatesStateWhileQueryIsPending() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()
        var queryCompleted = false
        let query = PendingCommand(
            packet: [0x01], sequence: 1, timeout: 60,
            responseMatcher: { $0.opcode == 0x0681 })

        XCTAssertTrue(session.enqueueQuery(query) { _ in queryCompleted = true })
        transport.receive("aa 0d 00 00 04 02 24 06 00 01 02 01 64 02 64")

        XCTAssertEqual(session.state.battery.left?.level, 100)
        XCTAssertEqual(session.state.battery.right?.level, 100)
        XCTAssertFalse(queryCompleted)
    }

    func testMatchingQueryResponseReducesBeforeCompletion() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()
        var levelSeenByCompletion: Int?
        let query = PendingCommand(
            packet: [0x01], sequence: 1, timeout: 60,
            responseMatcher: { $0.opcode == 0x0681 })

        XCTAssertTrue(session.enqueueQuery(
            query,
            decodeResponse: { _ in [.battery(.left, .init(level: 80))] },
            completion: { _ in levelSeenByCompletion = session.state.battery.left?.level }))
        transport.receive("aa 07 00 00 06 81 10 00 00")

        XCTAssertEqual(session.state.battery.left?.level, 80)
        XCTAssertEqual(levelSeenByCompletion, 80)
    }
}
