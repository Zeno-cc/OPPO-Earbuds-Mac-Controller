/// State of a feature whose value may not be available yet or may not be supported
/// by the connected device.
public enum FeatureState<Value: Equatable>: Equatable {
    case unsupported
    case unknown
    case loading
    case ready(Value)
    case failed(String)
}

public enum DeviceInformationSource: Equatable {
    /// Stable information selected by the device profile rather than read from the buds.
    case profileMetadata
    /// Information returned by the earbuds over the vendor control channel.
    case remoteQuery
}

public struct DeviceInformationField: Equatable {
    public var value: String
    public var source: DeviceInformationSource

    public init(_ value: String, source: DeviceInformationSource) {
        self.value = value
        self.source = source
    }
}

public struct DeviceInformation: Equatable {
    public var modelIdentifier: DeviceInformationField
    public var firmwareVersion: DeviceInformationField

    public init(modelIdentifier: DeviceInformationField,
                firmwareVersion: DeviceInformationField) {
        self.modelIdentifier = modelIdentifier
        self.firmwareVersion = firmwareVersion
    }
}

/// A battery percentage and its charging state are separate observations.
/// Either value may be unavailable, and `0` is a valid percentage rather than a
/// synonym for an unknown reading.
public struct BatteryReading: Equatable {
    public var level: Int?
    public var isCharging: Bool?

    public init(level: Int? = nil, isCharging: Bool? = nil) {
        self.level = level
        self.isCharging = isCharging
    }
}

public struct BatteryState: Equatable {
    public var left: BatteryReading?
    public var right: BatteryReading?
    public var enclosure: BatteryReading?
    public var combined: BatteryReading?

    public init(left: BatteryReading? = nil,
                right: BatteryReading? = nil,
                enclosure: BatteryReading? = nil,
                combined: BatteryReading? = nil) {
        self.left = left
        self.right = right
        self.enclosure = enclosure
        self.combined = combined
    }
}
