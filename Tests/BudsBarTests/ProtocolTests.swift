import XCTest
@testable import BudsCore

final class ProtocolTests: XCTestCase {
    private func bytes(_ string: String) -> [UInt8] {
        string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
    }

    private func decode(_ hex: String,
                        profile: BudsProtocol.Profile = .t500Pro) throws -> [BudsProtocol.Update] {
        var buffer = bytes(hex)
        let frames = BudsProtocol.drainFrames(from: &buffer)
        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(buffer.isEmpty)
        let frame = try XCTUnwrap(frames.first)
        return BudsProtocol.interpret(frame, profile: profile)
    }

    private func frame(_ hex: String) throws -> BudsProtocol.Frame {
        var buffer = bytes(hex)
        let frames = BudsProtocol.drainFrames(from: &buffer)
        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(buffer.isEmpty)
        return try XCTUnwrap(frames.first)
    }

    func testT500BatteryAndUnavailableSlots() throws {
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50"),
            [.battery(.left, .init(level: 100)),
             .battery(.right, .init(level: 100)),
             .battery(.enclosure, .init(level: 80))])
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 10 08 00 01 03 01 64 02 64 03 00"),
            [.battery(.left, .init(level: 100)),
             .battery(.right, .init(level: 100)),
             .battery(.enclosure, nil)])
        XCTAssertEqual(
            try decode("aa 0d 00 00 04 02 99 06 00 01 02 01 64 03 00"),
            [.battery(.left, .init(level: 100)), .battery(.enclosure, nil)])
    }

    func testAir5BatteryAndChargingBit() throws {
        let profile = BudsProtocol.Profile.encoAir5Pro
        XCTAssertEqual(
            try decode("aa 0d 00 00 04 02 24 06 00 01 02 01 64 02 64", profile: profile),
            [.battery(.left, .init(level: 100, isCharging: false)),
             .battery(.right, .init(level: 100, isCharging: false))])
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 4f 08 00 01 03 01 e4 02 64 03 1e", profile: profile),
            [.battery(.left, .init(level: 100, isCharging: true)),
             .battery(.right, .init(level: 100, isCharging: false)),
             .battery(.enclosure, .init(level: 30, isCharging: false))])
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 b1 08 00 01 03 01 e4 02 e4 03 da", profile: profile),
            [.battery(.left, .init(level: 100, isCharging: true)),
             .battery(.right, .init(level: 100, isCharging: true)),
             .battery(.enclosure, .init(level: 90, isCharging: true))])
    }

    func testAir5ActiveBatteryResponse() throws {
        let response = try frame("aa 0d 00 00 06 81 02 06 00 00 02 01 64 02 64")
        XCTAssertEqual(
            BudsProtocol.interpretBatteryResponse(response, profile: .encoAir5Pro),
            [.battery(.left, .init(level: 100, isCharging: false)),
             .battery(.right, .init(level: 100, isCharging: false))])

        let emptyBattery = try frame("aa 0b 00 00 06 81 02 04 00 00 01 01 00")
        XCTAssertEqual(
            BudsProtocol.interpretBatteryResponse(emptyBattery, profile: .encoAir5Pro),
            [.battery(.left, .init(level: 0, isCharging: false))])

        let rightInCase = try frame(
            "aa 0f 00 00 06 81 05 08 00 00 03 01 64 02 e4 03 5a")
        XCTAssertEqual(
            BudsProtocol.interpretBatteryResponse(rightInCase, profile: .encoAir5Pro),
            [.battery(.left, .init(level: 100, isCharging: false)),
             .battery(.right, .init(level: 100, isCharging: true)),
             .battery(.enclosure, .init(level: 90, isCharging: false))])

        let leftInCase = try frame(
            "aa 0f 00 00 06 81 0a 08 00 00 03 01 e4 02 64 03 5a")
        XCTAssertEqual(
            BudsProtocol.interpretBatteryResponse(leftInCase, profile: .encoAir5Pro),
            [.battery(.left, .init(level: 100, isCharging: true)),
             .battery(.right, .init(level: 100, isCharging: false)),
             .battery(.enclosure, .init(level: 90, isCharging: false))])

        let pluggedIn = try frame(
            "aa 0f 00 00 06 81 16 08 00 00 03 01 e4 02 e4 03 da")
        XCTAssertEqual(
            BudsProtocol.interpretBatteryResponse(pluggedIn, profile: .encoAir5Pro),
            [.battery(.left, .init(level: 100, isCharging: true)),
             .battery(.right, .init(level: 100, isCharging: true)),
             .battery(.enclosure, .init(level: 90, isCharging: true))])

        let malformed = try frame("aa 0b 00 00 06 81 02 04 00 00 02 01 64")
        XCTAssertTrue(
            BudsProtocol.interpretBatteryResponse(malformed, profile: .encoAir5Pro).isEmpty)
        XCTAssertTrue(
            BudsProtocol.interpretBatteryResponse(response, profile: .t500Pro).isEmpty)
    }

    func testT500NoiseModesAndLevels() throws {
        XCTAssertEqual(try decode("aa 0b 00 00 04 02 9b 04 00 03 01 01 01"), [.noiseMode(.off)])
        XCTAssertEqual(try decode("aa 0b 00 00 04 02 9b 04 00 03 01 01 02"), [.noiseMode(.transparency)])

        let values: [(String, ANCLevel)] = [
            ("04", .mild), ("08", .max), ("10", .moderate), ("20", .smart),
        ]
        for (wire, level) in values {
            XCTAssertEqual(
                try decode("aa 0b 00 00 04 02 9b 04 00 03 01 01 \(wire)"),
                [.noiseMode(.noiseCancellation), .ancLevel(level)])
        }
    }

    func testAir5NoiseModesAndLevels() throws {
        let profile = BudsProtocol.Profile.encoAir5Pro
        let values: [(String, ANCLevel)] = [
            ("10 00", .max), ("20 00", .moderate), ("40 00", .mild), ("80 00", .smart),
        ]
        for (wire, level) in values {
            XCTAssertEqual(
                try decode("aa 0c 00 00 04 02 60 05 00 03 01 01 \(wire)", profile: profile),
                [.noiseMode(.noiseCancellation), .ancLevel(level)])
        }
        XCTAssertEqual(
            try decode("aa 0c 00 00 04 02 67 05 00 03 01 01 08 00", profile: profile),
            [.noiseMode(.off)])
        XCTAssertEqual(
            try decode("aa 0c 00 00 04 02 67 05 00 03 01 01 00 01", profile: profile),
            [.noiseMode(.transparency)])
    }

    func testAir5EqualizerQueryAndReportFixtures() throws {
        let original = try frame("aa 09 00 00 0f 81 03 02 00 00 00")
        let vocals = try frame("aa 09 00 00 0f 81 06 02 00 00 02")
        let bass = try frame("aa 09 00 00 0f 81 08 02 00 00 01")

        XCTAssertEqual(
            BudsProtocol.interpretEqualizerResponse(original, profile: .encoAir5Pro),
            [.equalizer(.original)])
        XCTAssertEqual(
            BudsProtocol.interpretEqualizerResponse(vocals, profile: .encoAir5Pro),
            [.equalizer(.vocals)])
        XCTAssertEqual(
            BudsProtocol.interpretEqualizerResponse(bass, profile: .encoAir5Pro),
            [.equalizer(.bass)])
        XCTAssertEqual(
            try decode("aa 08 00 00 04 05 f8 01 00 02", profile: .encoAir5Pro),
            [.equalizer(.vocals)])
        XCTAssertTrue(BudsProtocol.interpretEqualizerResponse(
            original, profile: .t500Pro).isEmpty)
    }

    func testAir5GameModeQueryFixtures() throws {
        let enabled = try frame("aa 0b 00 00 0d 81 0e 04 00 00 01 06 01")
        let disabled = try frame("aa 0b 00 00 0d 81 0c 04 00 00 01 06 00")
        let multiple = try frame("aa 0d 00 00 0d 81 02 06 00 00 02 06 01 28 00")

        XCTAssertEqual(
            BudsProtocol.interpretGameModeResponse(enabled, profile: .encoAir5Pro),
            [.gameMode(true)])
        XCTAssertEqual(
            BudsProtocol.interpretGameModeResponse(disabled, profile: .encoAir5Pro),
            [.gameMode(false)])
        XCTAssertEqual(
            BudsProtocol.interpretGameModeResponse(multiple, profile: .encoAir5Pro),
            [.gameMode(true)])
        XCTAssertTrue(BudsProtocol.interpretGameModeResponse(
            enabled, profile: .t500Pro).isEmpty)
    }

    func testAir5SoundFeatureResponsesRejectMalformedValues() throws {
        let badEQ = try frame("aa 09 00 00 0f 81 03 02 00 00 ff")
        let badGame = try frame("aa 0b 00 00 0d 81 0e 04 00 00 01 06 02")
        let shortGame = try frame("aa 09 00 00 0d 81 0e 02 00 00 ff")

        XCTAssertTrue(BudsProtocol.interpretEqualizerResponse(
            badEQ, profile: .encoAir5Pro).isEmpty)
        XCTAssertTrue(BudsProtocol.interpretGameModeResponse(
            badGame, profile: .encoAir5Pro).isEmpty)
        XCTAssertTrue(BudsProtocol.interpretGameModeResponse(
            shortGame, profile: .encoAir5Pro).isEmpty)
    }

    func testSmartCompanionReportsAreIgnored() throws {
        XCTAssertTrue(try decode("aa 0b 00 00 04 02 48 04 00 03 04 01 10").isEmpty)
        XCTAssertTrue(
            try decode("aa 0c 00 00 04 02 64 05 00 03 04 01 40 00",
                       profile: .encoAir5Pro).isEmpty)
    }

    func testPlacementReports() throws {
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 98 08 00 02 03 01 00 02 03 03 04"),
            [.placement(.left, .inCase), .placement(.right, .inUse)])
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 a0 08 00 02 03 01 00 02 00 03 04"),
            [.placement(.left, .inCase), .placement(.right, .inCase)])
    }

    func testAir5PlacementReportsUseProfileSpecificValues() throws {
        let profile = BudsProtocol.Profile.encoAir5Pro
        XCTAssertEqual(
            try decode(
                "aa 0f 00 00 04 02 5b 08 00 02 03 01 05 02 04 03 04",
                profile: profile),
            [.placement(.left, .inUse), .placement(.right, .inCase)])
        XCTAssertEqual(
            try decode(
                "aa 0f 00 00 04 02 63 08 00 02 03 01 04 02 05 03 04",
                profile: profile),
            [.placement(.left, .inCase), .placement(.right, .inUse)])
        XCTAssertEqual(
            try decode(
                "aa 0f 00 00 04 02 5a 08 00 02 03 01 05 02 07 03 04",
                profile: profile),
            [.placement(.left, .inUse)])
    }

    func testFrameDecoderHandlesFragmentationCoalescingAndResync() {
        let battery = bytes("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50")
        let mode = bytes("aa 0b 00 00 04 02 1a 04 00 03 01 01 08")

        var fragmented = Array(battery.prefix(6))
        XCTAssertTrue(BudsProtocol.drainFrames(from: &fragmented).isEmpty)
        fragmented.append(contentsOf: battery.dropFirst(6))
        XCTAssertEqual(BudsProtocol.drainFrames(from: &fragmented).count, 1)
        XCTAssertTrue(fragmented.isEmpty)

        var coalesced = mode + battery
        XCTAssertEqual(BudsProtocol.drainFrames(from: &coalesced).count, 2)
        XCTAssertTrue(coalesced.isEmpty)

        var garbage = [0xff, 0x00] + battery
        XCTAssertEqual(BudsProtocol.drainFrames(from: &garbage).count, 1)
        XCTAssertTrue(garbage.isEmpty)
    }

    func testFrameDecoderKeepsIncompleteTailAndDrainsThreeFrames() {
        let battery = bytes("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50")
        let mode = bytes("aa 0b 00 00 04 02 1a 04 00 03 01 01 08")

        var incomplete = Array(battery.dropLast(2))
        let originalTail = incomplete
        XCTAssertTrue(BudsProtocol.drainFrames(from: &incomplete).isEmpty)
        XCTAssertEqual(incomplete, originalTail)

        var coalesced = mode + battery + mode
        let frames = BudsProtocol.drainFrames(from: &coalesced)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map(\.raw), [mode, battery, mode])
        XCTAssertTrue(coalesced.isEmpty)
    }

    func testFrameDecoderDoesNotMergeGameResponseWithFollowingFrame() {
        let game = bytes("aa 0b 00 00 0d 81 0e 04 00 00 01 06 01")
        let equalizer = bytes("aa 09 00 00 0f 81 0f 02 00 00 02")
        var coalesced = game + equalizer

        let frames = BudsProtocol.drainFrames(from: &coalesced)

        XCTAssertEqual(frames.map(\.raw), [game, equalizer])
        XCTAssertTrue(coalesced.isEmpty)
    }

    func testFrameDecoderResyncsAfterConflictingLengthFields() {
        // Header length says the frame ends at byte 9, while payload length says it needs
        // one more byte. The decoder must reject that boundary and find the following frame.
        let conflicting = bytes("aa 07 00 00 04 02 01 01 00")
        let battery = bytes("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50")
        var buffer = conflicting + battery

        let frames = BudsProtocol.drainFrames(from: &buffer)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.raw, battery)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testMalformedAndUnknownFramesDoNotProduceUpdates() throws {
        var malformed = bytes("aa 08 00 00 04 02 01 02 00 01")
        XCTAssertTrue(BudsProtocol.drainFrames(from: &malformed).isEmpty)

        // The tagged-list count promises three pairs, but each payload contains only two.
        // A truncated status report must not partially overwrite otherwise valid state.
        XCTAssertTrue(try decode(
            "aa 0d 00 00 04 02 24 06 00 01 03 01 64 02 64").isEmpty)
        XCTAssertTrue(try decode(
            "aa 0d 00 00 04 02 24 06 00 02 03 01 00 02 03").isEmpty)

        XCTAssertTrue(try decode("aa 0b 00 00 04 02 1a 04 00 03 01 01 7f").isEmpty)

        var encoder = OPOPacketEncoder()
        var nonStatus = try XCTUnwrap(encoder.encodeSetNoiseMode(.off, profile: .t500Pro))
        let frame = try XCTUnwrap(BudsProtocol.drainFrames(from: &nonStatus).first)
        XCTAssertTrue(BudsProtocol.interpret(frame).isEmpty)
    }

    func testExactCommandPackets() {
        let mappings: [(BudsProtocol.Profile, NoiseMode, ANCLevel?, UInt8)] = [
            (.t500Pro, .off, nil, 0x01),
            (.t500Pro, .transparency, nil, 0x02),
            (.t500Pro, .noiseCancellation, nil, 0x08),
            (.t500Pro, .noiseCancellation, .mild, 0x04),
            (.t500Pro, .noiseCancellation, .moderate, 0x10),
            (.t500Pro, .noiseCancellation, .smart, 0x20),
            (.encoAir5Pro, .off, nil, 0x01),
            (.encoAir5Pro, .transparency, nil, 0x04),
            (.encoAir5Pro, .noiseCancellation, nil, 0x02),
            (.encoAir5Pro, .noiseCancellation, .max, 0x10),
            (.encoAir5Pro, .noiseCancellation, .moderate, 0x20),
            (.encoAir5Pro, .noiseCancellation, .mild, 0x40),
            (.encoAir5Pro, .noiseCancellation, .smart, 0x80),
        ]

        for (profile, mode, level, value) in mappings {
            var encoder = OPOPacketEncoder()
            XCTAssertEqual(
                encoder.encodeSetNoiseMode(mode, level: level, profile: profile),
                [0xaa, 0x0a, 0x00, 0x00, 0x04, 0x04,
                 0x01, 0x03, 0x00, 0x01, 0x01, value])
        }

        var unknownEncoder = OPOPacketEncoder()
        XCTAssertNil(unknownEncoder.encodeSetNoiseMode(.off, profile: .unknown))
    }

    func testHandshakeAndSequencePacketsAreExact() {
        var encoder = OPOPacketEncoder()
        XCTAssertEqual(
            encoder.encodeHello(),
            [0xaa, 0x07, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00])
        XCTAssertEqual(
            encoder.encodeBatteryQuery(profile: .encoAir5Pro),
            [0xaa, 0x07, 0x00, 0x00, 0x06, 0x01, 0x02, 0x00, 0x00])
        XCTAssertEqual(
            encoder.encodeDeviceInformationQuery(profile: .encoAir5Pro),
            [0xaa, 0x07, 0x00, 0x00, 0x05, 0x01, 0x03, 0x00, 0x00])
        XCTAssertEqual(
            encoder.encodeEqualizerQuery(profile: .encoAir5Pro),
            [0xaa, 0x07, 0x00, 0x00, 0x0f, 0x01, 0x04, 0x00, 0x00])
        XCTAssertEqual(
            encoder.encodeGameModeQuery(profile: .encoAir5Pro),
            [0xaa, 0x09, 0x00, 0x00, 0x0d, 0x01, 0x05, 0x02, 0x00, 0x01, 0x06])
        XCTAssertEqual(
            encoder.encodeSetEqualizer(.vocals, profile: .encoAir5Pro),
            [0xaa, 0x08, 0x00, 0x00, 0x06, 0x04, 0x06, 0x01, 0x00, 0x02])
        XCTAssertEqual(
            encoder.encodeSetGameMode(false, profile: .encoAir5Pro),
            [0xaa, 0x09, 0x00, 0x00, 0x03, 0x04, 0x07, 0x02, 0x00, 0x06, 0x00])
        XCTAssertNil(encoder.encodeBatteryQuery(profile: .t500Pro))
        XCTAssertNil(encoder.encodeDeviceInformationQuery(profile: .t500Pro))
        XCTAssertNil(encoder.encodeEqualizerQuery(profile: .t500Pro))
        XCTAssertNil(encoder.encodeGameModeQuery(profile: .t500Pro))
        XCTAssertNil(encoder.encodeSetEqualizer(.original, profile: .t500Pro))
        XCTAssertNil(encoder.encodeSetGameMode(true, profile: .t500Pro))
    }

    func testAir5DeviceInformationFixture() throws {
        let response = try frame(
            "aa 27 00 00 05 81 03 20 00 00 04 31 2c 32 2c 31 35 38 2c 32 2c 32 2c 31 35 38 2c 33 2c 31 2c 30 31 2c 33 2c 32 2c 31 30 35")

        XCTAssertEqual(
            BudsProtocol.interpretDeviceInformationResponse(
                response, profile: .encoAir5Pro),
            [.deviceInformation(DeviceInformation(
                modelIdentifier: DeviceInformationField(
                    "OPPO Enco Air5 Pro", source: .profileMetadata),
                firmwareVersion: DeviceInformationField(
                    "158.158.105", source: .remoteQuery)))])
        XCTAssertTrue(BudsProtocol.interpretDeviceInformationResponse(
            response, profile: .t500Pro).isEmpty)
    }

    func testDeviceInformationRejectsShortAndMalformedPayloads() throws {
        var shortBytes = BudsProtocol.makeFrame(
            0, 0, 0x05, 0x81, sequence: 3,
            payload: [0, 4] + Array("1,2,158".utf8))
        let shortFrame = try XCTUnwrap(BudsProtocol.drainFrames(from: &shortBytes).first)
        XCTAssertTrue(BudsProtocol.interpretDeviceInformationResponse(
            shortFrame, profile: .encoAir5Pro).isEmpty)

        var malformedBytes = BudsProtocol.makeFrame(
            0, 0, 0x05, 0x81, sequence: 3, payload: [0, 4, 0xff])
        let malformedFrame = try XCTUnwrap(
            BudsProtocol.drainFrames(from: &malformedBytes).first)
        XCTAssertTrue(BudsProtocol.interpretDeviceInformationResponse(
            malformedFrame, profile: .encoAir5Pro).isEmpty)
    }

    func testDeviceInformationIgnoresUnknownCompleteEntry() throws {
        let csv = "1,2,158,2,2,158,3,1,01,3,2,105,9,9,future"
        var bytes = BudsProtocol.makeFrame(
            0, 0, 0x05, 0x81, sequence: 3,
            payload: [0, 5] + Array(csv.utf8))
        let response = try XCTUnwrap(BudsProtocol.drainFrames(from: &bytes).first)

        XCTAssertEqual(
            BudsProtocol.interpretDeviceInformationResponse(
                response, profile: .encoAir5Pro),
            [.deviceInformation(DeviceInformation(
                modelIdentifier: DeviceInformationField(
                    "OPPO Enco Air5 Pro", source: .profileMetadata),
                firmwareVersion: DeviceInformationField(
                    "158.158.105", source: .remoteQuery)))])
    }

    func testProfileRegistryDoesNotGuessUnknownDevices() {
        XCTAssertEqual(BudsProtocol.Profile.forDeviceName("OPPO Enco Air5 Pro"), .encoAir5Pro)
        XCTAssertEqual(BudsProtocol.Profile.forDeviceName("realme Buds T500 Pro"), .t500Pro)
        XCTAssertEqual(
            DeviceProfileRegistry.resolve(DeviceIdentity(
                advertisedName: "用户自定义名称",
                modelIdentifier: "OPPO Enco Air5 Pro")),
            .encoAir5Pro)
        XCTAssertEqual(BudsProtocol.Profile.forDeviceName("unknown"), .unknown)
        XCTAssertEqual(BudsProtocol.Profile.forDeviceName(nil), .unknown)
        XCTAssertFalse(BudsProtocol.Profile.unknown.capabilities.contains(.noiseControl))
        XCTAssertEqual(
            BudsProtocol.Profile.encoAir5Pro.initialSyncPlan,
            [.battery, .deviceInformation, .equalizer, .gameMode])
        XCTAssertTrue(BudsProtocol.Profile.t500Pro.initialSyncPlan.isEmpty)
        XCTAssertTrue(BudsProtocol.Profile.unknown.initialSyncPlan.isEmpty)
    }

    func testUnknownProfileKeepsGenericBatteryReadOnly() throws {
        XCTAssertEqual(
            try decode(
                "aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50",
                profile: .unknown),
            [.battery(.left, .init(level: 100)),
             .battery(.right, .init(level: 100)),
             .battery(.enclosure, .init(level: 80))])

        var encoder = OPOPacketEncoder()
        XCTAssertNil(encoder.encodeSetNoiseMode(.transparency, profile: .unknown))
    }

    func testDeviceSelectionRequiresAChoiceWhenSeveralDevicesHaveNoPreference() {
        let addresses = ["BB-BB-BB-BB-BB-BB", "AA:AA:AA:AA:AA:AA"]
        XCTAssertEqual(
            DeviceSelectionPolicy.selectAddress(
                from: addresses,
                forcedAddress: "CC-CC-CC-CC-CC-CC",
                preferredAddress: "BB:BB:BB:BB:BB:BB"),
            "CC:CC:CC:CC:CC:CC")
        XCTAssertEqual(
            DeviceSelectionPolicy.selectAddress(
                from: addresses,
                forcedAddress: nil,
                preferredAddress: "BB:BB:BB:BB:BB:BB"),
            "BB:BB:BB:BB:BB:BB")
        XCTAssertEqual(
            DeviceSelectionPolicy.selectAddress(
                from: addresses,
                forcedAddress: nil,
                preferredAddress: "DD:DD:DD:DD:DD:DD"),
            nil)
        XCTAssertEqual(
            DeviceSelectionPolicy.selectAddress(
                from: ["AA-AA-AA-AA-AA-AA"],
                forcedAddress: nil,
                preferredAddress: nil),
            "AA:AA:AA:AA:AA:AA")
    }
}
