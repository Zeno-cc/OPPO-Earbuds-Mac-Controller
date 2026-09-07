import Foundation

public enum CustomEQAction: UInt8 { case create = 1, update = 2, delete = 3 }

/// Wire fields verified against the installed official plugin's EqInfo and command parser.
public struct CustomEqualizer: Equatable {
    public let name: String
    public let frequencies: [UInt16]
    public let gains: [Int8]
    public let prefix: [UInt8]
    public var id: UInt8 { prefix[3] }
    public var isSelected: Bool { prefix[0] == 1 }
    public static let bandFrequencies: [UInt16] = [31,62,125,250,500,1000,2000,4000,8000,16000]

    public static func newCurve(name: String) -> Self {
        Self(name: name, frequencies: bandFrequencies, gains: Array(repeating: 0, count: 10),
             prefix: [0,250,6,0]) // Official new EqInfo leaves ID at zero; the earbud assigns it.
    }

    public func renamed(_ name: String) -> Self {
        Self(name: name, frequencies: frequencies, gains: gains, prefix: prefix)
    }

    public func selecting(_ selected: Bool) -> Self {
        Self(name: name, frequencies: frequencies, gains: gains,
             prefix: [selected ? 1 : 0] + Array(prefix.dropFirst()))
    }

    public func hasSameContent(as other: Self) -> Bool {
        name == other.name && frequencies == other.frequencies && gains == other.gains
            && prefix[1...2] == other.prefix[1...2]
    }

    public func replacingGains(_ values: [Int8]) -> Self? {
        guard values.count == 10, values.allSatisfy({ (-6...6).contains($0) }) else { return nil }
        return Self(name: name, frequencies: frequencies, gains: values, prefix: prefix)
    }

    public var writePayload: [UInt8]? {
        payload(for: .update)
    }

    public func payload(for action: CustomEQAction) -> [UInt8]? {
        let bytes = Array(name.utf8)
        guard prefix.count == 4, prefix[0] <= 1, Array(prefix[1...2]) == [250,6],
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              bytes.count <= 0xff - 7 - 36, frequencies == Self.bandFrequencies,
              replacingGains(gains) != nil else { return nil }
        var payload: [UInt8] = [action.rawValue] + Array(prefix.dropFirst()) + [UInt8(bytes.count)] + bytes + [10]
        for (frequency, gain) in zip(frequencies, gains) {
            payload += [UInt8(truncatingIfNeeded: frequency), UInt8(frequency >> 8), UInt8(bitPattern: gain)]
        }
        return payload
    }

    public static func decode(_ payload: [UInt8]) -> Self? {
        guard let list = decodeList(payload), list.count == 1 else { return nil }
        return list[0]
    }

    public static func decodeList(_ payload: [UInt8]) -> [Self]? {
        guard payload.count >= 2, payload[0] == 0 else { return nil }
        var result: [Self] = []
        var offset = 2
        for _ in 0..<Int(payload[1]) {
        guard offset + 5 < payload.count, payload[offset] <= 1 else { return nil }
        let nameStart = offset + 5
        let nameEnd = nameStart + Int(payload[offset + 4])
        guard nameEnd < payload.count,
              let name = String(bytes: payload[nameStart..<nameEnd], encoding: .utf8),
              payload[nameEnd] == 10,
              payload.count >= nameEnd + 1 + 30 else { return nil }
        var frequencies: [UInt16] = []
        var gains: [Int8] = []
        for offset in stride(from: nameEnd + 1, to: nameEnd + 31, by: 3) {
            frequencies.append(UInt16(payload[offset]) | UInt16(payload[offset + 1]) << 8)
            gains.append(Int8(bitPattern: payload[offset + 2]))
        }
        guard frequencies == [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000] else { return nil }
        let curve = Self(name: name, frequencies: frequencies, gains: gains,
                         prefix: Array(payload[offset..<offset+4]))
        guard !result.contains(where: { $0.id == curve.id }) else { return nil }
        result.append(curve)
        offset = nameEnd + 31
        }
        return offset == payload.count ? result : nil
    }
}
