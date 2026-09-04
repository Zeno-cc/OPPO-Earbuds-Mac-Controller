import BudsCore

struct HUDSnapshot: Equatable {
    let deviceName: String
    let isConnected: Bool
    let battery: BatteryPresentation
    let noiseControlText: String?
    let equalizerText: String?

    var hasPresentationDetails: Bool {
        !battery.items.isEmpty || noiseControlText != nil || equalizerText != nil
    }

    init(buds: Buds, event: ConnectionHUDEvent) {
        deviceName = buds.name
        isConnected = buds.isConnected

        guard event != .unexpectedDisconnected else {
            battery = BatteryPresentation(
                vendor: BatteryState(),
                system: BatteryState(),
                placement: EarbudsPlacementState())
            noiseControlText = nil
            equalizerText = nil
            return
        }

        battery = buds.batteryPresentation
        if let mode = buds.mode {
            if mode == .noiseCancellation, let level = buds.ancLevel {
                noiseControlText = "\(mode.label) · \(level.label)"
            } else {
                noiseControlText = mode.label
            }
        } else {
            noiseControlText = nil
        }
        if case .ready(let preset) = buds.equalizerFeature {
            equalizerText = preset.label
        } else {
            equalizerText = nil
        }
    }
}
