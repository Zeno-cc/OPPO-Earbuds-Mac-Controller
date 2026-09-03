import Foundation

public enum NoiseMode: String, CaseIterable, Identifiable {
    case noiseCancellation
    case off
    case transparency

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .noiseCancellation: return "降噪"
        case .off: return "关闭"
        case .transparency: return "通透"
        }
    }

    public var symbol: String {
        switch self {
        case .noiseCancellation: return "person.crop.circle"
        case .off: return "person.crop.circle.fill"
        case .transparency: return "person.crop.circle.badge.questionmark"
        }
    }
}

/// How hard noise cancellation works. realme Link calls these Mild / Moderate / Max, and
/// offers a fourth, Smart, which picks a level for you.
/// Declared strongest-first, matching realme Link's own order — `allCases` is what the
/// picker renders, and it is deliberately not the wire order.
public enum ANCLevel: String, CaseIterable, Identifiable {
    case max
    case moderate
    case mild
    case smart

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mild: return "轻度"
        case .moderate: return "中度"
        case .max: return "深度"
        case .smart: return "智能"
        }
    }

    public var detail: String {
        switch self {
        case .mild: return "适合家庭和办公室等安静场所"
        case .moderate: return "适合街道和商场等嘈杂场所"
        case .max: return "适合飞机和火车等非常嘈杂的场所"
        case .smart: return "耳机自动选择降噪强度"
        }
    }
}

/// Wire format for the `oppointeraction` RFCOMM channel on realme/OPPO earbuds.
///
/// Pure functions over bytes — no I/O — so `selfCheck()` can exercise them against
/// recorded traffic without the hardware present.
///
///     aa <len> <b2> <b3> <opcode:u16be> <seq> <payloadLen:u16le> <payload…>
///
/// `len` counts every byte after itself, so a frame is `len + 2` bytes long. There is no
/// trailing checksum — the length accounts for the payload exactly.
///
/// The payload is a tagged list: `<type> <count>` followed by `count` (id, value) pairs.
public enum BudsProtocol {

    public static let sync: UInt8 = 0xaa
    /// The only opcode observed: an unsolicited device status report.
    public static let opcodeStatusReport: UInt16 = 0x0402

    public struct Frame {
        public var opcode: UInt16
        public var sequence: UInt8
        public var payload: [UInt8]
        public var raw: [UInt8]
    }

    public enum Update: Equatable {
        case noiseMode(NoiseMode)
        /// nil means noise cancellation is on but the profile does not recognise the level.
        /// Only reported alongside a `.noiseMode(.noiseCancellation)`, so the last known
        /// level survives a trip through Off or Transparency.
        case ancLevel(ANCLevel?)
        /// One slot at a time, and nil means "reported as unknown" — not "absent".
        ///
        /// A battery frame can carry a subset of the three slots, so a slot that is missing
        /// must keep its last value while a slot that is present but unreadable must be
        /// cleared. Bundling all three into one update collapsed those two cases together,
        /// and a case that had gone to sleep kept showing its last percentage forever.
        case battery(BatterySlot, Int?)
        /// Where one bud is. Only emitted for values `BudPlacement` recognises.
        case placement(BatterySlot, BudPlacement)
    }

    public enum BatterySlot: UInt8 {
        case left = 0x01
        case right = 0x02
        case enclosure = 0x03
    }

    /// Where a bud is, decoded from the `02` block — the one thing that tells a bud charging
    /// in the case from a bud in use.
    ///
    /// The block is a per-slot list keyed by the same ids as the battery one. Captured with
    /// the right bud worn and the left in an open case it read `01 00  02 03  03 04`, and
    /// with both buds in the case `01 00  02 00  03 04`: the worn bud's slot is the only one
    /// that moved. The enclosure's own value (`04`) is something else and stays undecoded, so
    /// it falls out of `init?(rawValue:)` on its own rather than needing a special case.
    ///
    /// Only the two values above are known. A bud out of the case but not in an ear may well
    /// report a third, so an unrecognised value means "no idea" and the UI leaves the cell
    /// alone rather than guessing it into one of these.
    public enum BudPlacement: UInt8 {
        case inCase = 0x00
        case inUse = 0x03
    }

    // MARK: - Payload types

    private enum PayloadType: UInt8 {
        case battery = 0x01
        /// Per-slot placement, keyed by the same ids as `battery`. It was read as "some other
        /// setting" for a while because it moves whenever the mode changes — which is also
        /// when buds get taken out and put back. See `BudPlacement`.
        case placement = 0x02
        case noiseMode = 0x03
    }

    /// Entry id carrying the mode inside a `noiseMode` payload.
    private static let noiseModeID: UInt8 = 0x01

    // MARK: - Sending

    /// Builds a frame, filling in both length fields.
    static func makeFrame(_ b2: UInt8, _ b3: UInt8, _ b4: UInt8, _ b5: UInt8,
                          sequence: UInt8, payload: [UInt8]) -> [UInt8] {
        // `len` is a single byte covering the whole frame, so the payload cannot exceed
        // what it can count. Every caller here sends three bytes or fewer; without this the
        // overflow would surface as an arithmetic trap inside the conversion below.
        precondition(payload.count <= 0xff - 7, "payload too long for a one-byte length")
        var frame: [UInt8] = [sync, 0, b2, b3, b4, b5, sequence,
                              UInt8(payload.count & 0xff), UInt8(payload.count >> 8)]
        frame += payload
        frame[1] = UInt8(frame.count - 2)     // len counts every byte after itself
        return frame
    }

    /// OPOv1 categories. The buds' status notifications arrive on `.status`.
    enum Category: UInt8 {
        case system = 0x00
        case status = 0x04
    }

    /// Subcommands within a category.
    enum Subcommand: UInt8 {
        case hello = 0x01
        case setNoiseMode = 0x04
    }

    // MARK: - Receiving

    /// Pulls every complete frame out of `buffer`, leaving any partial tail behind.
    /// RFCOMM delivers arbitrary chunks, so frames both split and coalesce.
    public static func drainFrames(from buffer: inout [UInt8]) -> [Frame] {
        var frames: [Frame] = []

        while true {
            // Resynchronise: drop anything before the next sync byte.
            guard let start = buffer.firstIndex(of: sync) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }

            guard buffer.count >= 2 else { break }
            let total = Int(buffer[1]) + 2
            guard total >= 9 else {
                // Not a plausible frame — drop the sync byte and look for the next one.
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= total else { break }   // wait for the rest

            let raw = Array(buffer[0..<total])
            let payloadLength = Int(raw[7]) | Int(raw[8]) << 8
            if 9 + payloadLength == total {
                frames.append(Frame(
                    opcode: UInt16(raw[4]) << 8 | UInt16(raw[5]),
                    sequence: raw[6],
                    payload: Array(raw[9..<total]),
                    raw: raw))
                buffer.removeFirst(total)
            } else {
                // Length fields disagree: this was not a frame boundary after all.
                buffer.removeFirst()
            }
        }

        return frames
    }

    public static func interpret(_ frame: Frame, profile: Profile = .t500Pro) -> [Update] {
        guard frame.opcode == opcodeStatusReport else { return [] }

        let payload = frame.payload
        guard payload.count >= 2, let type = PayloadType(rawValue: payload[0]) else { return [] }

        let count = Int(payload[1])
        var pairs: [(UInt8, UInt8)] = []
        var index = 2
        for _ in 0..<count {
            guard index + 1 < payload.count else { break }
            pairs.append((payload[index], payload[index + 1]))
            index += 2
        }

        switch type {
        case .battery:
            return pairs.compactMap { id, value in
                guard let slot = BatterySlot(rawValue: id) else { return nil }
                // A slot reports 0 while it is asleep or shut rather than dropping out of
                // the frame. Air5 also uses values outside the percentage range (for example
                // `e4`) as an unavailable sentinel. Neither is a real battery reading.
                let percentage = Int(value)
                return .battery(slot, (1...100).contains(percentage) ? percentage : nil)
            }

        case .noiseMode:
            // While Smart is running the buds emit a second `03` block, with a count of 4
            // and a single pair, carrying the level Smart has currently settled on. Acting
            // on it would show a level here that the phone is not showing, so it is
            // ignored — a real mode report always has exactly one pair.
            guard count == 1 else { return [] }

            guard payload.count >= 4, payload[2] == noiseModeID else { return [] }
            let value: UInt16
            if profile.modeValueBytes == 2 {
                guard payload.count >= 5 else { return [] }
                value = UInt16(payload[3]) | UInt16(payload[4]) << 8
            } else {
                value = UInt16(payload[3])
            }
            guard let decoded = profile.decodeNoiseMode(value) else { return [] }
            guard decoded.mode == .noiseCancellation else { return [.noiseMode(decoded.mode)] }
            // The ANC strength lives in the same field as the mode, so one report yields both.
            return [.noiseMode(decoded.mode), .ancLevel(decoded.level)]

        case .placement:
            return pairs.compactMap { id, value in
                guard let slot = BatterySlot(rawValue: id),
                      let placement = BudPlacement(rawValue: value)
                else { return nil }
                return .placement(slot, placement)
            }
        }
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    // MARK: - Self check

    /// Replays real captured frames. Runs at launch in debug builds.
    public static func selfCheck() {
        func bytes(_ string: String) -> [UInt8] {
            string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        }

        // Battery report captured while both buds read 100% and the case read 80%.
        var buffer = bytes("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50")
        var frames = drainFrames(from: &buffer)
        assert(frames.count == 1, "one battery frame")
        assert(buffer.isEmpty, "buffer fully consumed")
        assert(frames[0].opcode == opcodeStatusReport)
        assert(interpret(frames[0]) == [.battery(.left, 100), .battery(.right, 100),
                                        .battery(.enclosure, 80)])

        // Same report with the case asleep — must read as unknown, not 0%.
        buffer = bytes("aa 0f 00 00 04 02 10 08 00 01 03 01 64 02 64 03 00")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]) == [.battery(.left, 100), .battery(.right, 100),
                                        .battery(.enclosure, nil)],
               "a sleeping case reads as unknown, and says so rather than staying silent")

        // A partial frame: left and case only, no right. The absent slot must produce no
        // update at all, so whatever the UI already had for it survives.
        buffer = bytes("aa 0d 00 00 04 02 99 06 00 01 02 01 64 03 00")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]) == [.battery(.left, 100), .battery(.enclosure, nil)],
               "an absent slot is not the same as an unknown one")

        // Noise mode, captured while commanding each mode in turn.
        for (wire, expected) in [("01", NoiseMode.off), ("02", .transparency)] {
            buffer = bytes("aa 0b 00 00 04 02 9b 04 00 03 01 01 \(wire)")
            frames = drainFrames(from: &buffer)
            assert(interpret(frames[0]) == [.noiseMode(expected)], "wire \(wire)")
        }

        // The ANC levels, captured off the phone one tap at a time. Both the mode and the
        // level come out of the single byte.
        for (wire, expected) in [("04", ANCLevel.mild),
                                 ("08", .max),
                                 ("10", .moderate)] {
            buffer = bytes("aa 0b 00 00 04 02 9b 04 00 03 01 01 \(wire)")
            frames = drainFrames(from: &buffer)
            assert(interpret(frames[0]) == [.noiseMode(.noiseCancellation), .ancLevel(expected)],
                   "ANC level wire \(wire)")
        }

        // Smart is a real level, not an effective-level guess.
        buffer = bytes("aa 0b 00 00 04 02 48 04 00 03 01 01 20")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]) == [.noiseMode(.noiseCancellation), .ancLevel(.smart)],
               "T500 Smart reports ANC with the Smart level")

        // Smart's companion block, captured immediately after the frame above. Count is 4
        // with one pair; acting on it would show Moderate while the phone shows Smart.
        buffer = bytes("aa 0b 00 00 04 02 48 04 00 03 04 01 10")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]).isEmpty, "Smart's effective-level echo is ignored")

        // Off and Transparency carry no level, so the last known one survives them.
        buffer = bytes("aa 0b 00 00 04 02 9b 04 00 03 01 01 01")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]) == [.noiseMode(.off)], "Off does not clear the level")

        // An unmapped mode value yields no update rather than a wrong one.
        buffer = bytes("aa 0b 00 00 04 02 1a 04 00 03 01 01 7f")
        frames = drainFrames(from: &buffer)
        assert(frames.count == 1 && buffer.isEmpty, "short frame")
        assert(interpret(frames[0]).isEmpty, "unknown mode value ignored")

        // The 0x02 block is placement, not the mode — captured with the right bud worn and
        // the left one sitting in an open case. The enclosure's own value is not a placement
        // and must drop out rather than being forced into one.
        buffer = bytes("aa 0f 00 00 04 02 98 08 00 02 03 01 00 02 03 03 04")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]) == [.placement(.left, .inCase), .placement(.right, .inUse)],
               "0x02 block is placement, and carries no mode")

        // Same frame shape with both buds back in the case: only the worn bud's slot moved.
        buffer = bytes("aa 0f 00 00 04 02 a0 08 00 02 03 01 00 02 00 03 04")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]) == [.placement(.left, .inCase), .placement(.right, .inCase)],
               "both buds in the case")

        // The battery report drops a bud in the case instead of reporting it as unknown, so
        // its slot goes absent and whatever the UI had for it would otherwise stand forever.
        // Placement is what tells the two apart.
        buffer = bytes("aa 0d 00 00 04 02 97 06 00 01 02 02 64 03 00")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0]) == [.battery(.right, 100), .battery(.enclosure, nil)],
               "a bud in the case is absent from the battery report, not zero")

        // The frame we send to set a mode must be well formed, carry the set opcode
        // rather than the report opcode, and put the right value in the payload.
        var encoder = OPOPacketEncoder()
        var sent = encoder.encodeSetNoiseMode(.transparency, profile: .t500Pro)!
        assert(sent == bytes("aa 0a 00 00 04 04 \(String(format: "%02x", sent[6])) 03 00 01 01 02"),
               "set frame layout: \(hex(sent))")
        frames = drainFrames(from: &sent)
        assert(frames.count == 1 && sent.isEmpty, "set frame parses as one frame")
        assert(frames[0].opcode == 0x0404, "set uses the set opcode, not the report one")
        assert(interpret(frames[0]).isEmpty, "a set frame is not a status update")

        // Commanding a level puts that level's byte in the mode field, and a level is
        // ignored for the modes that do not have one.
        assert(encoder.encodeSetNoiseMode(.noiseCancellation, level: .moderate,
                                          profile: .t500Pro)?.last == 0x10, "T500 set Moderate")
        assert(encoder.encodeSetNoiseMode(.noiseCancellation, level: .mild,
                                          profile: .t500Pro)?.last == 0x04, "T500 set Mild")
        assert(encoder.encodeSetNoiseMode(.noiseCancellation,
                                          profile: .t500Pro)?.last == Profile.t500Pro.wire(for: .max),
               "T500 ANC defaults to Max")
        assert(encoder.encodeSetNoiseMode(.off, level: .mild,
                                          profile: .t500Pro)?.last == 0x01,
               "level does not leak into Off")

        // Every command we can send must round-trip back to the state it asked for.
        for level in ANCLevel.allCases {
            var command = encoder.encodeSetNoiseMode(.noiseCancellation, level: level,
                                                     profile: .t500Pro)!
            let value = command.last!
            command = bytes("aa 0b 00 00 04 02 9b 04 00 03 01 01 \(String(format: "%02x", value))")
            frames = drainFrames(from: &command)
            assert(interpret(frames[0]) == [.noiseMode(.noiseCancellation), .ancLevel(level)],
                   "\(level.label) round-trips")
        }

        // Air5 Pro uses the same OPOv1 frame but a different mode vocabulary. These are the
        // seven command/reply values from the phone capture: ANC entry, Max, Moderate, Mild,
        // Smart, Off, Transparency. The reported mode is a UInt16 little-endian value.
        let air5 = Profile.encoAir5Pro

        // Live Air5 Pro capture from the Mac RFCOMM channel. Its `01` block carries only
        // the active buds here; the case is simply absent until it is awake and reports.
        buffer = bytes("aa 0d 00 00 04 02 24 06 00 01 02 01 64 02 64")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0], profile: air5)
               == [.battery(.left, 100), .battery(.right, 100)],
               "Air5 per-bud battery frame")

        // Air5 uses e4 for an unavailable bud while still reporting the other bud and case.
        // Keep the known slots and mark only the sentinel-bearing slot as unknown.
        buffer = bytes("aa 0f 00 00 04 02 4f 08 00 01 03 01 e4 02 64 03 1e")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0], profile: air5)
               == [.battery(.left, nil), .battery(.right, 100), .battery(.enclosure, 30)],
               "Air5 unavailable-bud sentinel with case battery")

        for (wire, expected) in [("10 00", ANCLevel.max),
                                 ("20 00", .moderate),
                                 ("40 00", .mild),
                                 ("80 00", .smart)] {
            buffer = bytes("aa 0c 00 00 04 02 60 05 00 03 01 01 \(wire)")
            frames = drainFrames(from: &buffer)
            assert(interpret(frames[0], profile: air5)
                   == [.noiseMode(.noiseCancellation), .ancLevel(expected)],
                   "Air5 ANC value \(wire)")
        }
        for (wire, expected) in [("08 00", NoiseMode.off), ("00 01", .transparency)] {
            buffer = bytes("aa 0c 00 00 04 02 67 05 00 03 01 01 \(wire)")
            frames = drainFrames(from: &buffer)
            assert(interpret(frames[0], profile: air5) == [.noiseMode(expected)],
                   "Air5 mode value \(wire)")
        }
        buffer = bytes("aa 0c 00 00 04 02 64 05 00 03 04 01 40 00")
        frames = drainFrames(from: &buffer)
        assert(interpret(frames[0], profile: air5).isEmpty,
               "Air5 Smart effective-level companion is ignored")

        assert(encoder.encodeSetNoiseMode(.noiseCancellation, profile: air5)?.last == 0x02,
               "Air5 ANC entry command")
        assert(encoder.encodeSetNoiseMode(.noiseCancellation, level: .max, profile: air5)?.last == 0x10,
               "Air5 set Max")
        assert(encoder.encodeSetNoiseMode(.noiseCancellation, level: .moderate, profile: air5)?.last == 0x20,
               "Air5 set Moderate")
        assert(encoder.encodeSetNoiseMode(.noiseCancellation, level: .mild, profile: air5)?.last == 0x40,
               "Air5 set Mild")
        assert(encoder.encodeSetNoiseMode(.noiseCancellation, level: .smart, profile: air5)?.last == 0x80,
               "Air5 set Smart")
        assert(encoder.encodeSetNoiseMode(.off, profile: air5)?.last == 0x01, "Air5 set Off")
        assert(encoder.encodeSetNoiseMode(.transparency, profile: air5)?.last == 0x04,
               "Air5 set Transparency")

        // Two frames arriving coalesced in one read.
        buffer = bytes("aa 0b 00 00 04 02 1a 04 00 03 01 01 08")
             + bytes("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50")
        frames = drainFrames(from: &buffer)
        assert(frames.count == 2 && buffer.isEmpty, "coalesced frames")

        // One frame split across two reads: the tail must be held, not misparsed.
        let whole = bytes("aa 0f 00 00 04 02 0c 08 00 01 03 01 64 02 64 03 50")
        buffer = Array(whole[0..<6])
        assert(drainFrames(from: &buffer).isEmpty, "partial frame withheld")
        buffer.append(contentsOf: whole[6...])
        frames = drainFrames(from: &buffer)
        assert(frames.count == 1 && buffer.isEmpty, "frame completed across reads")
        assert(interpret(frames[0]) == [.battery(.left, 100), .battery(.right, 100),
                                        .battery(.enclosure, 80)])

        // Leading garbage before the sync byte must be skipped, not fatal.
        buffer = bytes("ff ff") + whole
        frames = drainFrames(from: &buffer)
        assert(frames.count == 1 && buffer.isEmpty, "resynchronised past garbage")

        FileHandle.standardError.write(Data("BudsProtocol.selfCheck passed\n".utf8))
    }
}
