public struct OPOPacketEncoder {
    public private(set) var sequence: UInt8 = 0

    public init() {}

    public mutating func encodeHello() -> [UInt8] {
        BudsProtocol.makeFrame(
            0x00, 0x00,
            BudsProtocol.Category.system.rawValue,
            BudsProtocol.Subcommand.hello.rawValue,
            sequence: nextSequence(), payload: [])
    }

    public mutating func encodeSetNoiseMode(
        _ mode: NoiseMode,
        level: ANCLevel? = nil,
        profile: BudsProtocol.Profile
    ) -> [UInt8]? {
        guard let value = profile.commandValue(for: mode, level: level) else { return nil }
        return BudsProtocol.makeFrame(
            0x00, 0x00,
            BudsProtocol.Category.status.rawValue,
            BudsProtocol.Subcommand.setNoiseMode.rawValue,
            sequence: nextSequence(), payload: [0x01, 0x01, value])
    }

    private mutating func nextSequence() -> UInt8 {
        sequence &+= 1
        return sequence
    }
}
