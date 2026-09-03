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

    public mutating func encodeBatteryQuery(profile: BudsProtocol.Profile) -> [UInt8]? {
        guard profile.capabilities.contains(.activeBatteryQuery) else { return nil }
        return BudsProtocol.makeFrame(
            0x00, 0x00, 0x06, 0x01,
            sequence: nextSequence(), payload: [])
    }

    public mutating func encodeDeviceInformationQuery(
        profile: BudsProtocol.Profile
    ) -> [UInt8]? {
        guard profile.capabilities.contains(.deviceInformation) else { return nil }
        return BudsProtocol.makeFrame(
            0x00, 0x00, 0x05, 0x01,
            sequence: nextSequence(), payload: [])
    }

    public mutating func encodeEqualizerQuery(
        profile: BudsProtocol.Profile
    ) -> [UInt8]? {
        guard profile.capabilities.contains(.equalizer) else { return nil }
        return BudsProtocol.makeFrame(
            0x00, 0x00, 0x0f, 0x01,
            sequence: nextSequence(), payload: [])
    }

    public mutating func encodeSetEqualizer(
        _ preset: EQPreset,
        profile: BudsProtocol.Profile
    ) -> [UInt8]? {
        guard profile.capabilities.contains(.equalizer) else { return nil }
        return BudsProtocol.makeFrame(
            0x00, 0x00, 0x06, 0x04,
            sequence: nextSequence(), payload: [preset.rawValue])
    }

    public mutating func encodeGameModeQuery(
        profile: BudsProtocol.Profile
    ) -> [UInt8]? {
        guard profile.capabilities.contains(.gameMode) else { return nil }
        return BudsProtocol.makeFrame(
            0x00, 0x00, 0x0d, 0x01,
            sequence: nextSequence(), payload: [0x01, BudsProtocol.gameModeFeatureID])
    }

    public mutating func encodeSetGameMode(
        _ enabled: Bool,
        profile: BudsProtocol.Profile
    ) -> [UInt8]? {
        guard profile.capabilities.contains(.gameMode) else { return nil }
        return BudsProtocol.makeFrame(
            0x00, 0x00, 0x03, 0x04,
            sequence: nextSequence(),
            payload: [BudsProtocol.gameModeFeatureID, enabled ? 0x01 : 0x00])
    }

    private mutating func nextSequence() -> UInt8 {
        sequence &+= 1
        return sequence
    }
}
