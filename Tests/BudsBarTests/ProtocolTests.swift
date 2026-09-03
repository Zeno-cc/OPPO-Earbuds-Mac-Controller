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

    func testT500BatteryAndUnavailableSlots() throws {
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50"),
            [.battery(.left, 100), .battery(.right, 100), .battery(.enclosure, 80)])
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 10 08 00 01 03 01 64 02 64 03 00"),
            [.battery(.left, 100), .battery(.right, 100), .battery(.enclosure, nil)])
        XCTAssertEqual(
            try decode("aa 0d 00 00 04 02 99 06 00 01 02 01 64 03 00"),
            [.battery(.left, 100), .battery(.enclosure, nil)])
    }

    func testAir5BatteryAndUnavailableSentinel() throws {
        let profile = BudsProtocol.Profile.encoAir5Pro
        XCTAssertEqual(
            try decode("aa 0d 00 00 04 02 24 06 00 01 02 01 64 02 64", profile: profile),
            [.battery(.left, 100), .battery(.right, 100)])
        XCTAssertEqual(
            try decode("aa 0f 00 00 04 02 4f 08 00 01 03 01 e4 02 64 03 1e", profile: profile),
            [.battery(.left, nil), .battery(.right, 100), .battery(.enclosure, 30)])
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
            encoder.encodeHello(),
            [0xaa, 0x07, 0x00, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00])
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
    }

    func testUnknownProfileKeepsGenericBatteryReadOnly() throws {
        XCTAssertEqual(
            try decode(
                "aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50",
                profile: .unknown),
            [.battery(.left, 100), .battery(.right, 100), .battery(.enclosure, 80)])

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
