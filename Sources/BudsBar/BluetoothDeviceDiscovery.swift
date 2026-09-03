import BudsCore
import Foundation
import IOBluetooth

enum BluetoothDeviceDiscovery {
    static let controlServiceUUID: [UInt8] = [
        0x00, 0x00, 0x07, 0x9a, 0xd1, 0x02, 0x11, 0xe1,
        0x9b, 0x23, 0x00, 0x02, 0x5b, 0x00, 0xa5, 0xa5,
    ]

    static func pairedOPODevices() -> [IOBluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        let uuid = IOBluetoothSDPUUID(bytes: controlServiceUUID,
                                      length: controlServiceUUID.count)
        return paired
            .filter { $0.getServiceRecord(for: uuid) != nil }
            .sorted { normalizedAddress($0.addressString) < normalizedAddress($1.addressString) }
    }

    static func select(forcedAddress: String?, preferredAddress: String?) -> IOBluetoothDevice? {
        let devices = pairedOPODevices()
        let selected = DeviceSelectionPolicy.selectAddress(
            from: devices.compactMap(\.addressString),
            forcedAddress: forcedAddress,
            preferredAddress: preferredAddress)
        guard let selected else { return nil }

        if let device = devices.first(where: {
            normalizedAddress($0.addressString) == selected
        }) {
            return device
        }
        return IOBluetoothDevice(addressString: selected)
    }

    /// Returns a newly materialised paired-device wrapper for the address.
    ///
    /// IOBluetooth device objects can keep zero-valued battery indicators after a
    /// disconnect/reconnect cycle even though a fresh wrapper already exposes the new
    /// `batteryPercentSingle` value. Battery reads use this snapshot instead of replacing
    /// the live device object that owns connection notifications and the RFCOMM channel.
    static func pairedDeviceSnapshot(address: String) -> IOBluetoothDevice? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        let wanted = normalizedAddress(address)
        return paired.first { normalizedAddress($0.addressString) == wanted }
    }

    static func normalizedAddress(_ value: String?) -> String {
        DeviceSelectionPolicy.normalizedAddress(value ?? "")
    }
}
