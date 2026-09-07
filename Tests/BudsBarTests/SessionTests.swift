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

    func testCustomCurveWriteRequiresFullReadbackAndRejectsStaleDraft() throws {
        for scenario in 0...2 {
            let matching = scenario == 0
            let transport = FakeTransport()
            let clock = TestClock()
            let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                         now: { clock.now }, scheduler: clock.schedule)
            let payload: [UInt8] = "00 01 01 fa 06 04 07 e8 87 aa e8 a8 82 31 0a 1f 00 00 3e 00 00 7d 00 00 fa 00 00 f4 01 00 e8 03 00 d0 07 00 a0 0f 00 40 1f 00 80 3e ff"
                .split(separator: " ").map { UInt8($0, radix: 16)! }
            let baseline = try XCTUnwrap(CustomEqualizer.decode(payload))
            session.open()
            XCTAssertTrue(session.refreshCustomEqualizer())
            clock.advance(by: 0.2)
            var query = try XCTUnwrap(transport.sent.last)
            XCTAssertEqual(Array(query[4...5]), [0x22,1])
            transport.eventHandler?(.bytes(BudsProtocol.makeFrame(0,0,0x22,0x81,
                sequence: query[6], payload: payload)))
            let gains: [Int8] = [-6,6,0,0,0,0,0,0,0,-1]
            XCTAssertTrue(session.set(customEqualizer: baseline, gains: gains))
            XCTAssertFalse(session.set(customEqualizer: baseline, gains: gains))
            clock.advance(by: 0.4)
            XCTAssertEqual(session.state.operations[.equalizer]?.phase, .sent)
            query = try XCTUnwrap(transport.sent.last)
            XCTAssertEqual(Array(query[4...5]), [0x22,1])
            var returned = payload
            returned[17] = UInt8(bitPattern: matching ? -6 : -5)
            returned[20] = 6
            if scenario == 2 { session.close() }
            transport.eventHandler?(.bytes(BudsProtocol.makeFrame(0,0,0x22,0x81,
                sequence: query[6], payload: returned)))
            clock.advance(by: 3)
            XCTAssertEqual(session.state.operations[.equalizer]?.phase,
                           scenario == 2 ? .cancelled : matching ? .confirmed : .differentState)
            XCTAssertFalse(session.set(customEqualizer: baseline, gains: gains))
            XCTAssertEqual(transport.sent.filter { Array($0[4...5]) == [0x18,4] }.count, 1)
            session.close()
            XCTAssertEqual(session.state.customEqualizerFeature, .unknown)
        }
    }

    func testUnverifiedCustomFormatReportsPrefixWithoutSending() throws {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                     scheduler: clock.schedule)
        // Synthetic alternate prefix: proves rejection reporting, not a new wire format.
        let payload: [UInt8] = "00 01 00 fb 06 04 07 e8 87 aa e8 a8 82 31 0a 1f 00 00 3e 00 00 7d 00 00 fa 00 00 f4 01 00 e8 03 00 d0 07 00 a0 0f 00 40 1f 00 80 3e ff"
            .split(separator: " ").map { UInt8($0, radix: 16)! }
        let curve = try XCTUnwrap(CustomEqualizer.decode(payload))
        session.open()
        XCTAssertTrue(session.refreshCustomEqualizer())
        clock.advance(by: 0.2)
        let query = try XCTUnwrap(transport.sent.last)
        transport.eventHandler?(.bytes(BudsProtocol.makeFrame(0,0,0x22,0x81,
            sequence: query[6], payload: payload)))
        XCTAssertTrue(try XCTUnwrap(session.customEqualizerRejection(curve, gains: curve.gains))
            .contains("00 FB 06 04"))
        XCTAssertFalse(session.set(customEqualizer: curve, gains: curve.gains))
        XCTAssertFalse(transport.sent.contains { Array($0[4...5]) == [0x18,4] })
    }

    func testCustomEQManagementConfirmsCreateUpdateDeleteFromDeviceList() throws {
        for action in [CustomEQAction.create, .update, .delete] {
            for succeeds in [true, false] {
                let transport = FakeTransport()
                let clock = TestClock()
                let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                    now: { clock.now }, scheduler: clock.schedule)
                let existing = CustomEqualizer(name: "原曲线", frequencies: CustomEqualizer.bandFrequencies,
                    gains: Array(repeating: 0, count: 10), prefix: [0,250,6,4])
                func payload(_ values: [CustomEqualizer]) -> [UInt8] {
                    [0,UInt8(values.count)] + values.flatMap { [$0.prefix[0]] + Array($0.writePayload!.dropFirst()) }
                }
                session.open()
                XCTAssertTrue(session.refreshCustomEqualizer())
                clock.advance(by: 0.2)
                var query = try XCTUnwrap(transport.sent.last)
                transport.eventHandler?(.bytes(BudsProtocol.makeFrame(0,0,0x22,0x81,
                    sequence: query[6], payload: payload([existing]))))
                let target = action == .create ? CustomEqualizer.newCurve(name: "新增")
                    : action == .update ? existing.renamed("改名") : existing
                XCTAssertTrue(session.manageCustomEqualizer(action,
                    baseline: action == .create ? nil : existing, target: target))
                XCTAssertFalse(session.manageCustomEqualizer(action,
                    baseline: action == .create ? nil : existing, target: target))
                clock.advance(by: 0.4)
                XCTAssertEqual(session.state.operations[.equalizer]?.phase, .sent)
                let write = try XCTUnwrap(transport.sent.first { Array($0[4...5]) == [0x18,4] })
                XCTAssertEqual(write[9], action.rawValue)
                var returned = [existing]
                if succeeds {
                    switch action {
                    case .create:
                        returned.append(CustomEqualizer(name: target.name, frequencies: target.frequencies,
                            gains: target.gains, prefix: [1,250,6,8]))
                    case .update:
                        returned = [CustomEqualizer(name: target.name, frequencies: target.frequencies,
                            gains: target.gains, prefix: [1,250,6,4])]
                    case .delete: returned = []
                    }
                }
                query = try XCTUnwrap(transport.sent.last)
                XCTAssertEqual(Array(query[4...5]), [0x22,1])
                transport.eventHandler?(.bytes(BudsProtocol.makeFrame(0,0,0x22,0x81,
                    sequence: query[6], payload: payload(returned))))
                clock.advance(by: 3)
                XCTAssertEqual(session.state.operations[.equalizer]?.phase, succeeds ? .confirmed : .differentState)
                XCTAssertEqual(transport.sent.filter { Array($0[4...5]) == [0x18,4] }.count, 1)
                session.close()
            }
        }
    }

    func testPhoneCustomListUpdatesAndPresetSwitchClearsCustomSelection() throws {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport, scheduler: clock.schedule)
        let curve = CustomEqualizer(name: "手机曲线", frequencies: CustomEqualizer.bandFrequencies,
            gains: Array(repeating: 0, count: 10), prefix: [1,250,6,9])
        let report = [UInt8(1),1] + Array(try XCTUnwrap(curve.writePayload).dropFirst())
        session.open()
        transport.eventHandler?(.bytes(BudsProtocol.makeFrame(0,0,6,5,sequence: 90, payload: report)))
        XCTAssertEqual(session.state.customEqualizerFeature, .ready([curve]))
        transport.receive("aa 08 00 00 04 05 f8 01 00 02")
        XCTAssertEqual(session.state.customEqualizerFeature, .ready([curve.selecting(false)]))
        XCTAssertFalse(session.manageCustomEqualizer(.delete, baseline: curve, target: curve))
        // A phone-side delete report empties the list without confirming any local operation.
        transport.eventHandler?(.bytes(BudsProtocol.makeFrame(0,0,6,5,sequence: 91, payload: [0])))
        XCTAssertEqual(session.state.customEqualizerFeature, .ready([]))
        XCTAssertNil(session.state.operations[.equalizer])
        session.close()
    }

    func testNoiseWriteWithoutReportReleasesPending() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                     scheduler: clock.schedule)
        session.open()
        XCTAssertTrue(session.set(mode: .transparency))
        clock.advance(by: 5)
        XCTAssertNil(session.state.pendingMode)
        XCTAssertNil(session.state.mode)
        XCTAssertEqual(transport.sent.filter { Array($0[4...5]) == [4, 4] }.count, 1)
    }

    func testUnknownEQReportClearsOldPresetSelection() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()
        transport.receive("aa 08 00 00 04 05 f8 01 00 02")
        XCTAssertEqual(session.state.equalizerFeature, .ready(.vocals))
        // Synthetic unknown mode, not evidence for a custom-EQ command.
        transport.receive("aa 08 00 00 04 05 f9 01 00 7f")
        XCTAssertEqual(session.state.equalizerFeature, .unknown)
    }

    func testUnknownPlacementAndDisconnectClearPreviouslyKnownPositions() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport)
        session.open()
        transport.receive("aa 0f 00 00 04 02 5b 08 00 02 03 01 05 02 04 03 04")
        transport.receive("aa 0f 00 00 04 02 5a 08 00 02 03 01 05 02 07 03 04")
        XCTAssertNil(session.state.placement.right)
        XCTAssertEqual(session.state.placement.left, .inUse)
        session.close()
        XCTAssertNil(session.state.placement.left)
    }

    func testDifferentNoiseReportKeepsConfirmationWindowOpen() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                     scheduler: clock.schedule)
        session.open()
        XCTAssertTrue(session.set(mode: .transparency))
        transport.receive("aa 0c 00 00 04 02 60 05 00 03 01 01 20 00")
        XCTAssertEqual(session.state.mode, .noiseCancellation)
        XCTAssertEqual(session.state.pendingMode, .transparency)
    }

    func testRestoredNoiseModeRequiresRememberedStrength() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .t500Pro, transport: transport,
                                     now: { clock.now }, scheduler: clock.schedule)
        session.open()
        XCTAssertTrue(session.set(mode: .noiseCancellation, rememberedLevel: .smart))
        transport.receive("aa 0b 00 00 04 02 9b 04 00 03 01 01 08")
        XCTAssertEqual(session.state.operations[.noise]?.phase, .sent)
        clock.advance(by: 3)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .differentState)
    }

    func testRestoredNoiseModeConfirmsMatchingStrength() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .t500Pro, transport: transport)
        session.open()
        XCTAssertTrue(session.set(mode: .noiseCancellation, rememberedLevel: .smart))
        transport.receive("aa 0b 00 00 04 02 48 04 00 03 01 01 20")
        XCTAssertEqual(session.state.operations[.noise]?.phase, .confirmed)
        XCTAssertNil(session.state.pendingANCLevel)
    }

    func testTransparencyDoesNotWaitForRememberedANCStrength() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .t500Pro, transport: transport)
        session.open()
        XCTAssertTrue(session.set(mode: .transparency, rememberedLevel: .smart))
        transport.receive("aa 0b 00 00 04 02 9b 04 00 03 01 01 02")
        XCTAssertEqual(session.state.operations[.noise]?.phase, .confirmed)
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

    func testConfirmationDeadlineStartsWhenQueuedWriteIsSent() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .t500Pro, transport: transport,
                                     now: { clock.now }, scheduler: clock.schedule)
        session.open()
        session.enqueueQuery(PendingCommand(packet: [1], sequence: 1, timeout: 5,
            retryLimit: 0, responseMatcher: { _ in false })) { _ in }
        XCTAssertTrue(session.set(mode: .transparency))
        XCTAssertEqual(session.state.operations[.noise]?.phase, .queued)
        XCTAssertNil(session.state.operations[.noise]?.deadline)
        clock.advance(by: 5)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .queued)
        clock.advance(by: 0.2)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .sent)
        XCTAssertEqual(session.state.operations[.noise]?.sentAt, 5.2)
        clock.advance(by: 2.9)
        XCTAssertEqual(session.state.pendingMode, .transparency)
        clock.advance(by: 0.2)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .timedOut)
    }

    func testOldDeadlineCannotClearOperationAfterReconnect() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .t500Pro, transport: transport,
                                     now: { clock.now }, scheduler: clock.schedule)
        session.open()
        XCTAssertTrue(session.set(mode: .transparency))
        let firstID = session.state.operations[.noise]?.id
        clock.advance(by: 1)
        session.close()
        XCTAssertEqual(session.state.operations[.noise]?.phase, .cancelled)
        XCTAssertNil(session.state.pendingMode)
        session.open()
        XCTAssertTrue(session.set(mode: .off))
        XCTAssertNotEqual(session.state.operations[.noise]?.id, firstID)
        clock.advance(by: 2.1)
        XCTAssertEqual(session.state.pendingMode, .off)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .sent)
        clock.advance(by: 1)
        XCTAssertNil(session.state.pendingMode)
    }

    func testDifferentStateIsReportedOnlyAtDeadlineAndCanStillConfirm() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                     now: { clock.now }, scheduler: clock.schedule)
        session.open()
        XCTAssertTrue(session.set(mode: .transparency))
        transport.receive("aa 0c 00 00 04 02 60 05 00 03 01 01 20 00")
        clock.advance(by: 1)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .sent)
        transport.receive("aa 0c 00 00 04 02 67 05 00 03 01 01 00 01")
        XCTAssertEqual(session.state.operations[.noise]?.phase, .confirmed)
        clock.advance(by: 3)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .confirmed)
    }

    func testWriteDispatchFailureReleasesPendingAndRetainsActualValue() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .t500Pro, transport: transport,
                                     scheduler: clock.schedule)
        session.open()
        transport.sendSucceeds = false
        XCTAssertTrue(session.set(mode: .transparency)) // accepted, dispatch then fails
        XCTAssertEqual(session.state.operations[.noise]?.phase, .sendFailed)
        XCTAssertNil(session.state.pendingMode)
        XCTAssertNil(session.state.mode)
    }

    func testTransportFailureClosesChannelBeforeRetry() {
        let transport = FakeTransport()
        let session = EarbudsSession(profile: .t500Pro, transport: transport)
        session.open()
        XCTAssertTrue(session.set(mode: .off))
        transport.eventHandler?(.failed(TransportError("asynchronous write failure")))
        XCTAssertFalse(transport.isOpen)
        XCTAssertEqual(transport.closeCount, 1)
        XCTAssertEqual(session.state.operations[.noise]?.phase, .cancelled)
        session.open()
        XCTAssertEqual(session.connectionState, .ready)
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
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                     scheduler: clock.schedule)
        session.open()

        XCTAssertTrue(session.set(equalizer: .vocals))
        XCTAssertEqual(session.state.pendingEqualizer, .vocals)
        clock.advance(by: 0.2)
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
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                     scheduler: clock.schedule)
        session.open()

        XCTAssertTrue(session.set(gameMode: false))
        XCTAssertEqual(session.state.pendingGameMode, false)
        XCTAssertNotEqual(session.state.gameModeFeature, .ready(false))
        clock.advance(by: 0.2)
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

    func testMalformedGameModeReadBackKeepsConfirmedValueUntilOperationTimeout() {
        let transport = FakeTransport()
        let clock = TestClock()
        let session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                                     scheduler: clock.schedule)
        session.open()

        XCTAssertTrue(session.set(gameMode: true))
        clock.advance(by: 0.2)
        transport.receive("aa 0b 00 00 0d 81 03 04 00 00 01 06 01")
        XCTAssertEqual(session.state.gameModeFeature, .ready(true))

        var observedPendingClear = false
        session.onStateChange = {
            observedPendingClear = session.state.pendingGameMode == nil
        }
        XCTAssertTrue(session.set(gameMode: false))
        XCTAssertEqual(session.state.pendingGameMode, false)
        clock.advance(by: 0.4) // three urgent sends yield to initial battery refresh
        XCTAssertEqual(Array(transport.sent.last![4...5]), [0x06, 0x01])
        let batterySequence = transport.sent.last![6]
        transport.receive("aa 0d 00 00 06 81 \(String(format: "%02x", batterySequence)) 06 00 00 02 01 64 02 64")
        clock.advance(by: 0.2)
        XCTAssertEqual(Array(transport.sent.last![4...5]), [0x0d, 0x01])
        let sequence = transport.sent.last![6]
        transport.receive("aa 0b 00 00 0d 81 \(String(format: "%02x", sequence)) 04 00 00 01 06 02")
        XCTAssertEqual(session.state.pendingGameMode, false)
        XCTAssertEqual(session.state.gameModeFeature, .ready(true))
        XCTAssertEqual(session.state.soundRefresh[.gameMode], .failed("游戏模式响应格式异常"))
        clock.advance(by: 3)
        XCTAssertNil(session.state.pendingGameMode)
        XCTAssertEqual(session.state.gameModeFeature, .ready(true))
        XCTAssertEqual(session.state.operations[.gameMode]?.phase, .timedOut)
        XCTAssertTrue(observedPendingClear)
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
