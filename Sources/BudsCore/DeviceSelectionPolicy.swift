import Foundation

public enum DeviceSelectionPolicy {
    public static func selectAddress(from addresses: [String],
                                     forcedAddress: String?,
                                     preferredAddress: String?) -> String? {
        if let forcedAddress, !forcedAddress.isEmpty {
            return normalizedAddress(forcedAddress)
        }

        let available = Set(addresses.map(normalizedAddress))
        if let preferredAddress {
            let preferred = normalizedAddress(preferredAddress)
            if available.contains(preferred) { return preferred }
        }
        // With several devices and no remembered choice, selecting by array or address
        // order is deterministic but still arbitrary from the user's point of view. Leave
        // selection empty so the app can ask which earbuds should receive commands.
        guard available.count == 1 else { return nil }
        return available.first
    }

    public static func normalizedAddress(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: ":").uppercased()
    }
}
