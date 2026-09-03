import Foundation

public struct DeviceIdentity: Equatable {
    public var advertisedName: String?
    public var modelIdentifier: String?
    public var address: String?

    public init(advertisedName: String? = nil,
                modelIdentifier: String? = nil,
                address: String? = nil) {
        self.advertisedName = advertisedName
        self.modelIdentifier = modelIdentifier
        self.address = address
    }
}

public struct DeviceCapabilities: OptionSet, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let battery = Self(rawValue: 1 << 0)
    public static let placement = Self(rawValue: 1 << 1)
    public static let noiseControl = Self(rawValue: 1 << 2)
    public static let ancLevels = Self(rawValue: 1 << 3)
    public static let activeBatteryQuery = Self(rawValue: 1 << 4)
    public static let deviceInformation = Self(rawValue: 1 << 5)
    public static let equalizer = Self(rawValue: 1 << 6)
    public static let gameMode = Self(rawValue: 1 << 7)

    static let knownOPO: Self = [.battery, .placement, .noiseControl, .ancLevels]
    static let unknownOPO: Self = [.battery, .placement]
}

public enum DeviceProfileRegistry {
    private static let air5Names: Set<String> = ["oppoencoair5pro", "encoair5pro"]
    private static let t500Names: Set<String> = [
        "realmebudst500pro", "realmet500pro", "budst500pro",
    ]

    public static func resolve(_ identity: DeviceIdentity) -> BudsProtocol.Profile {
        let model = normalize(identity.modelIdentifier)
        let name = normalize(identity.advertisedName)
        if air5Names.contains(model) || air5Names.contains(name) { return .encoAir5Pro }
        if t500Names.contains(model) || t500Names.contains(name) { return .t500Pro }
        return .unknown
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}

extension BudsProtocol {
    public enum Profile: String, Equatable {
        case t500Pro
        case encoAir5Pro
        case unknown

        public static func forDeviceName(_ name: String?) -> Self {
            DeviceProfileRegistry.resolve(DeviceIdentity(advertisedName: name))
        }

        public var capabilities: DeviceCapabilities {
            switch self {
            case .t500Pro: return .knownOPO
            case .encoAir5Pro:
                return [
                    .knownOPO, .activeBatteryQuery, .deviceInformation, .equalizer, .gameMode,
                ]
            case .unknown: return .unknownOPO
            }
        }

        public var initialSyncPlan: [SyncFeature] {
            var plan: [SyncFeature] = []
            if capabilities.contains(.activeBatteryQuery) { plan.append(.battery) }
            if capabilities.contains(.deviceInformation) { plan.append(.deviceInformation) }
            if capabilities.contains(.equalizer) { plan.append(.equalizer) }
            if capabilities.contains(.gameMode) { plan.append(.gameMode) }
            return plan
        }

        public var modelIdentifier: String? {
            switch self {
            case .encoAir5Pro: return "OPPO Enco Air5 Pro"
            case .t500Pro: return "realme Buds T500 Pro"
            case .unknown: return nil
            }
        }

        public func commandValue(for mode: NoiseMode, level: ANCLevel?) -> UInt8? {
            switch self {
            case .t500Pro:
                switch mode {
                case .off: return 0x01
                case .transparency: return 0x02
                case .noiseCancellation: return wire(for: level ?? .max)
                }
            case .encoAir5Pro:
                switch mode {
                case .off: return 0x01
                case .transparency: return 0x04
                case .noiseCancellation: return level.flatMap(wire(for:)) ?? 0x02
                }
            case .unknown:
                return nil
            }
        }

        public func wire(for level: ANCLevel) -> UInt8? {
            switch self {
            case .t500Pro:
                switch level {
                case .mild: return 0x04
                case .max: return 0x08
                case .moderate: return 0x10
                case .smart: return 0x20
                }
            case .encoAir5Pro:
                switch level {
                case .max: return 0x10
                case .moderate: return 0x20
                case .mild: return 0x40
                case .smart: return 0x80
                }
            case .unknown:
                return nil
            }
        }

        public func decodeNoiseMode(_ value: UInt16) -> (mode: NoiseMode, level: ANCLevel?)? {
            switch self {
            case .t500Pro:
                switch value {
                case 0x01: return (.off, nil)
                case 0x02: return (.transparency, nil)
                case 0x04: return (.noiseCancellation, .mild)
                case 0x08: return (.noiseCancellation, .max)
                case 0x10: return (.noiseCancellation, .moderate)
                case 0x20: return (.noiseCancellation, .smart)
                default: return nil
                }
            case .encoAir5Pro:
                switch value {
                case 0x0008: return (.off, nil)
                case 0x0100: return (.transparency, nil)
                case 0x0010: return (.noiseCancellation, .max)
                case 0x0020: return (.noiseCancellation, .moderate)
                case 0x0040: return (.noiseCancellation, .mild)
                case 0x0080: return (.noiseCancellation, .smart)
                default: return nil
                }
            case .unknown:
                return nil
            }
        }

        public func decodePlacement(_ value: UInt8) -> BudPlacement? {
            switch self {
            case .t500Pro:
                switch value {
                case 0x00: return .inCase
                case 0x03: return .inUse
                default: return nil
                }
            case .encoAir5Pro:
                switch value {
                case 0x04: return .inCase
                case 0x05: return .inUse
                default: return nil
                }
            case .unknown:
                return nil
            }
        }

        public var modeValueBytes: Int {
            switch self {
            case .encoAir5Pro: return 2
            case .t500Pro: return 1
            case .unknown: return 0
            }
        }
    }

    public enum SyncFeature: Equatable {
        case battery
        case deviceInformation
        case equalizer
        case gameMode
    }
}
