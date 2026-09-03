import BudsCore
import Foundation
import IOBluetooth

final class RFCOMMTransport: NSObject, ControlTransport, IOBluetoothRFCOMMChannelDelegate {
    var eventHandler: ((ControlTransportEvent) -> Void)?
    private(set) var isOpen = false

    private let device: IOBluetoothDevice
    private let tracing: Bool
    private var channel: IOBluetoothRFCOMMChannel?
    private var isOpening = false

    init(device: IOBluetoothDevice, tracing: Bool) {
        self.device = device
        self.tracing = tracing
    }

    func open() {
        guard channel == nil, !isOpening else { return }
        isOpening = true

        DispatchQueue.global(qos: .userInitiated).async {
            self.device.performSDPQuery(nil)
            let uuid = IOBluetoothSDPUUID(
                bytes: BluetoothDeviceDiscovery.controlServiceUUID,
                length: BluetoothDeviceDiscovery.controlServiceUUID.count)
            var record: IOBluetoothSDPServiceRecord?
            for _ in 0..<40 {
                record = self.device.getServiceRecord(for: uuid)
                if record != nil { break }
                Thread.sleep(forTimeInterval: 0.05)
            }

            var channelID: BluetoothRFCOMMChannelID = 0
            guard let record else {
                DispatchQueue.main.async { self.fail("未找到耳机控制服务") }
                return
            }
            guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
                DispatchQueue.main.async { self.fail("耳机控制通道不可用") }
                return
            }

            DispatchQueue.main.async {
                defer { self.isOpening = false }
                var opened: IOBluetoothRFCOMMChannel?
                let result = self.device.openRFCOMMChannelAsync(
                    &opened, withChannelID: channelID, delegate: self)
                if result == kIOReturnSuccess {
                    self.channel = opened
                } else {
                    self.eventHandler?(.failed(TransportError(
                        "控制通道忙（IOReturn \(result)）")))
                }
            }
        }
    }

    func close() {
        channel?.close()
        channel = nil
        isOpening = false
        isOpen = false
    }

    @discardableResult
    func send(_ packet: [UInt8]) -> Bool {
        guard let channel, isOpen else { return false }
        var bytes = packet
        let result = bytes.withUnsafeMutableBytes { raw in
            channel.writeAsync(raw.baseAddress, length: UInt16(raw.count), refcon: nil)
        }
        if result != kIOReturnSuccess {
            eventHandler?(.failed(TransportError("写入失败（IOReturn \(result)）")))
            return false
        }
        return true
    }

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        isOpening = false
        guard error == kIOReturnSuccess else {
            self.channel = nil
            eventHandler?(.failed(TransportError(
                "打开控制通道失败（IOReturn \(error)）")))
            return
        }
        self.channel = channel
        isOpen = true
        eventHandler?(.opened)
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        let chunk = Array(UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        if tracing {
            AppLogger.transport.debug("RX \(BudsProtocol.hex(chunk), privacy: .public)")
        }
        eventHandler?(.bytes(chunk))
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        self.channel = nil
        isOpen = false
        eventHandler?(.closed)
    }

    private func fail(_ message: String) {
        isOpening = false
        eventHandler?(.failed(TransportError(message)))
    }
}
