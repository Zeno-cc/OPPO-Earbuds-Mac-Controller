import XCTest
@testable import BudsCore

final class CustomEqualizerTests: XCTestCase {
    // 2026-09-07 Bluetooth capture, 22/81 response: 16 kHz = -1.
    private let captured: [UInt8] = "00 01 01 fa 06 04 07 e8 87 aa e8 a8 82 31 0a 1f 00 00 3e 00 00 7d 00 00 fa 00 00 f4 01 00 e8 03 00 d0 07 00 a0 0f 00 40 1f 00 80 3e ff"
        .split(separator: " ").map { UInt8($0, radix: 16)! }

    func testCapturedCurveDecodesSignedGainAndUTF8Name() throws {
        let curve = try XCTUnwrap(CustomEqualizer.decode(captured))
        XCTAssertEqual(curve.name, "自訂1")
        XCTAssertEqual(curve.frequencies.last, 16000)
        XCTAssertEqual(curve.gains, [0,0,0,0,0,0,0,0,0,-1])
        XCTAssertEqual(curve.prefix, [1,250,6,4])
    }

    func testTruncatedOrUnsupportedPayloadDoesNotInventCurve() {
        for count in 0..<captured.count {
            XCTAssertNil(CustomEqualizer.decode(Array(captured.prefix(count))))
        }
        var failed = captured
        failed[0] = 1
        XCTAssertNil(CustomEqualizer.decode(failed))
        XCTAssertNil(CustomEqualizer.decode(captured + [0]))
    }

    func testWriteMatchesCapturedPayloadAndRejectsOutOfRangeGains() throws {
        let curve = try XCTUnwrap(CustomEqualizer.decode(captured))
        XCTAssertEqual(curve.writePayload, [2] + Array(captured.dropFirst(3)))
        XCTAssertNotNil(curve.replacingGains([-6,6,0,0,0,0,0,0,0,-1]))
        XCTAssertNil(curve.replacingGains([-7,0,0,0,0,0,0,0,0,0]))
        XCTAssertNil(curve.replacingGains([7,0,0,0,0,0,0,0,0,0]))
        XCTAssertNil(curve.replacingGains([0]))
        var encoder = OPOPacketEncoder()
        let frame = try XCTUnwrap(encoder.encodeSetCustomEqualizer(curve))
        XCTAssertEqual(Array(frame.dropFirst(9)), curve.writePayload)
        XCTAssertEqual(Array(frame[4...5]), [0x18, 0x04])
    }

    func testOfficialSchemaAllowsInactiveProfileAndMultipleDeviceIDs() throws {
        var inactive = captured
        inactive[2] = 0
        let curve = try XCTUnwrap(CustomEqualizer.decode(inactive))
        XCTAssertFalse(curve.isSelected)
        XCTAssertEqual(curve.id, 4)
        XCTAssertEqual(curve.writePayload, [2] + Array(captured.dropFirst(3)))
        var second = Array(captured.dropFirst(2))
        second[3] = 7
        let list = try XCTUnwrap(CustomEqualizer.decodeList([0,2] + Array(inactive.dropFirst(2)) + second))
        XCTAssertEqual(list.map(\.id), [4,7])
        XCTAssertEqual(CustomEqualizer.decodeList([0,0]), [])
        XCTAssertNil(CustomEqualizer.decodeList([0,2] + Array(inactive.dropFirst(2))))
        XCTAssertNil(CustomEqualizer.decodeList([0,2] + second + second))
    }

    func testCreateRenameAndDeleteUseOfficialActionAndUTF8ByteLength() throws {
        let new = CustomEqualizer.newCurve(name: "低音")
        let create = try XCTUnwrap(new.payload(for: .create))
        XCTAssertEqual(Array(create.prefix(5)), [1,250,6,0,6])
        let existing = try XCTUnwrap(CustomEqualizer.decode(captured)).renamed("人声")
        XCTAssertEqual(Array(try XCTUnwrap(existing.payload(for: .update)).prefix(5)), [2,250,6,4,6])
        XCTAssertEqual(Array(try XCTUnwrap(existing.payload(for: .delete)).prefix(5)), [3,250,6,4,6])
        XCTAssertNil(new.renamed(" ").writePayload)
        XCTAssertNil(new.renamed(String(repeating: "a", count: 213)).writePayload)
    }
}
