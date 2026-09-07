// Standalone receive logger for the verified oppointeraction service only.
// Prefer the app's BUDSBAR_TRACE: this tool opens its own channel and cannot capture
// Android's private TX/RX. Quit the app before using this standalone fallback.
//
// Run: swift Tools/sniff.swift
// Raw hex requires explicit BUDSBAR_TRACE_RAW=1. No protocol writes are sent.

import Foundation
import IOBluetooth

setvbuf(stdout, nil, _IOLBF, 0)

let controlServiceUUID: [UInt8] = [
    0x00, 0x00, 0x07, 0x9a, 0xd1, 0x02, 0x11, 0xe1,
    0x9b, 0x23, 0x00, 0x02, 0x5b, 0x00, 0xa5, 0xa5,
]
guard CommandLine.arguments.count == 1 else {
    print("Channel-number probing is not supported; use the verified SDP control service.")
    exit(1)
}
let rawTracing = ProcessInfo.processInfo.environment["BUDSBAR_TRACE_RAW"] == "1"

let start = Date()
func stamp() -> String { String(format: "%8.3f", Date().timeIntervalSince(start)) }
func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

/// Prefer an explicit address when several compatible devices are paired. Otherwise use the
/// same service-based discovery as the app, so the sniffer follows the currently paired Air5
/// Pro (or any other OPOv1 device) instead of a stale address from the author's test hardware.
func discoverDevice() -> IOBluetoothDevice? {
    if let forced = ProcessInfo.processInfo.environment["BUDSBAR_ADDRESS"] {
        return IOBluetoothDevice(addressString: forced)
    }
    guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        return nil
    }
    let uuid = IOBluetoothSDPUUID(bytes: controlServiceUUID, length: 16)
    let compatible = paired.filter { $0.getServiceRecord(for: uuid) != nil }
    return compatible.count == 1 ? compatible.first : nil
}

final class Sniffer: NSObject, IOBluetoothRFCOMMChannelDelegate {
    /// Ask the channel which one it is rather than trusting the id we requested.
    private func label(_ channel: IOBluetoothRFCOMMChannel!) -> String {
        let id = channel?.getID() ?? 0
        return "ch\(id) oppointeraction"
    }

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        print("[\(stamp())] \(label(channel)): \(error == kIOReturnSuccess ? "open" : "FAILED (\(error))")")
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        let detail = rawTracing ? " hex=\(hex(bytes))" : ""
        print("[\(stamp())] \(label(channel)): RX length=\(bytes.count)\(detail)")
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        print("[\(stamp())] \(label(channel)): closed")
    }
}

guard let device = discoverDevice() else {
    print("Cannot select one compatible paired device; use BUDSBAR_ADDRESS if needed.")
    exit(1)
}
print("[\(stamp())] selected device connected: \(device.isConnected())")
guard device.isConnected() else {
    print("buds are not connected — connect them first"); exit(1)
}

// The channel open silently never completes unless the device's SDP records have been
// fetched in this process first.
device.performSDPQuery(nil)
RunLoop.current.run(until: Date().addingTimeInterval(3))

var openChannels: [IOBluetoothRFCOMMChannel?] = []
var delegates: [Sniffer] = []          // keep alive; the channel does not retain them

let uuid = IOBluetoothSDPUUID(bytes: controlServiceUUID, length: 16)
var id: BluetoothRFCOMMChannelID = 0
guard let record = device.getServiceRecord(for: uuid),
      record.getRFCOMMChannelID(&id) == kIOReturnSuccess else {
    print("Verified control service has no RFCOMM channel; no channel was opened.")
    exit(1)
}
do {
    let sniffer = Sniffer()
    delegates.append(sniffer)
    var channel: IOBluetoothRFCOMMChannel?
    let result = device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: sniffer)
    if result == kIOReturnSuccess {
        openChannels.append(channel)
    } else {
        print("[\(stamp())] ch\(id): open failed (\(result))")
    }
}

print("[\(stamp())] listening on this Mac's control channel only; not a phone HCI capture")
RunLoop.current.run()
