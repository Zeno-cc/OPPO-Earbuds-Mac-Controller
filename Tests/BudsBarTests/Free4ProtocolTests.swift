import XCTest
@testable import BudsCore

final class Free4ProtocolTests: XCTestCase {
    private let profile = BudsProtocol.Profile.encoFree4

    private func bytes(_ string: String) -> [UInt8] {
        string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
    }

    private func decode(_ hex: String) throws -> [BudsProtocol.Update] {
        var buffer = bytes(hex)
        let frames = BudsProtocol.drainFrames(from: &buffer)
        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(buffer.isEmpty)
        return BudsProtocol.interpret(try XCTUnwrap(frames.first), profile: profile)
    }

    func testProfileRegistryAndCapabilities() {
        XCTAssertEqual(BudsProtocol.Profile.forDeviceName("OPPO Enco Free4"), .encoFree4)
        XCTAssertEqual(BudsProtocol.Profile.forDeviceName("Enco Free4"), .encoFree4)
        XCTAssertEqual(
            DeviceProfileRegistry.resolve(DeviceIdentity(
                advertisedName: "My Earbuds",
                modelIdentifier: "OPPO Enco Free4")),
            .encoFree4)

        let capabilities = profile.capabilities
        XCTAssertTrue(capabilities.contains(.battery))
        XCTAssertTrue(capabilities.contains(.noiseControl))
        XCTAssertTrue(capabilities.contains(.ancLevels))
        XCTAssertFalse(capabilities.contains(.placement))
        XCTAssertFalse(capabilities.contains(.activeBatteryQuery))
        XCTAssertFalse(capabilities.contains(.deviceInformation))
        XCTAssertFalse(capabilities.contains(.equalizer))
        XCTAssertFalse(capabilities.contains(.gameMode))
        XCTAssertTrue(profile.initialSyncPlan.isEmpty)
        XCTAssertEqual(profile.modelIdentifier, "OPPO Enco Free4")
        XCTAssertEqual(profile.modeValueBytes, 2)
    }

    func testCapturedNoiseReports() throws {
        let values: [(String, ANCLevel)] = [
            ("10 00", .max),
            ("20 00", .moderate),
            ("40 00", .mild),
            ("80 00", .smart),
        ]

        for (wire, level) in values {
            XCTAssertEqual(
                try decode("aa 0c 00 00 04 02 ff 05 00 03 01 01 \(wire)"),
                [.noiseMode(.noiseCancellation), .ancLevel(level)])
        }

        XCTAssertEqual(
            try decode("aa 0c 00 00 04 02 ff 05 00 03 01 01 08 00"),
            [.noiseMode(.off)])
        XCTAssertEqual(
            try decode("aa 0c 00 00 04 02 ff 05 00 03 01 01 00 01"),
            [.noiseMode(.transparency)])
    }

    func testAdaptiveReportPreservesTruthWithoutInventingStrength() throws {
        XCTAssertEqual(
            try decode("aa 0c 00 00 04 02 ff 05 00 03 01 01 00 08"),
            [.noiseMode(.noiseCancellation), .ancLevel(nil)])
    }

    func testNoiseCommandEncodingMatchesContributorMapping() {
        let mappings: [(NoiseMode, ANCLevel?, UInt8)] = [
            (.off, nil, 0x01),
            (.transparency, nil, 0x04),
            (.noiseCancellation, nil, 0x02),
            (.noiseCancellation, .max, 0x10),
            (.noiseCancellation, .moderate, 0x20),
            (.noiseCancellation, .mild, 0x40),
            (.noiseCancellation, .smart, 0x80),
        ]

        for (mode, level, value) in mappings {
            var encoder = OPOPacketEncoder()
            XCTAssertEqual(
                encoder.encodeSetNoiseMode(mode, level: level, profile: profile),
                [0xaa, 0x0a, 0x00, 0x00, 0x04, 0x04,
                 0x01, 0x03, 0x00, 0x01, 0x01, value])
        }
    }

    func testUnverifiedFeaturesRemainUnavailable() {
        var encoder = OPOPacketEncoder()
        XCTAssertNil(encoder.encodeBatteryQuery(profile: profile))
        XCTAssertNil(encoder.encodeDeviceInformationQuery(profile: profile))
        XCTAssertNil(encoder.encodeEqualizerQuery(profile: profile))
        XCTAssertNil(encoder.encodeGameModeQuery(profile: profile))
        XCTAssertNil(encoder.encodeSetEqualizer(.original, profile: profile))
        XCTAssertNil(encoder.encodeSetGameMode(true, profile: profile))
        XCTAssertNil(profile.decodePlacement(0x04))
    }
}
