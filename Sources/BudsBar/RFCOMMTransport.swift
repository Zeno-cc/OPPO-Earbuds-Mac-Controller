import BudsCore
import Foundation
import IOBluetooth

final class RFCOMMTransport: NSObject, ControlTransport {
    var eventHandler: ((ControlTransportEvent) -> Void)? {
        get { lifecycle.eventHandler }
        set { lifecycle.eventHandler = newValue }
    }
    var isOpen: Bool { lifecycle.isOpen }

    private let device: IOBluetoothDevice
    private let tracing: Bool
    private let rawTracing: Bool
    private let lifecycle = RFCOMMLifecycle<IOBluetoothRFCOMMChannel>()
    private var channelDelegate: ChannelDelegate?

    init(device: IOBluetoothDevice, tracing: Bool) {
        self.device = device
        self.tracing = tracing
        self.rawTracing = ProcessInfo.processInfo.environment["BUDSBAR_TRACE_RAW"] == "1"
    }

    func open() {
        guard let generation = lifecycle.beginOpen() else { return }

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
                DispatchQueue.main.async {
                    self.lifecycle.discoveryFailed("未找到耳机控制服务", generation: generation)
                }
                return
            }
            guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
                DispatchQueue.main.async {
                    self.lifecycle.discoveryFailed("耳机控制通道不可用", generation: generation)
                }
                return
            }

            DispatchQueue.main.async {
                guard self.lifecycle.acceptsDiscovery(generation) else { return }
                let delegate = ChannelDelegate(owner: self, generation: generation)
                self.channelDelegate = delegate
                var opened: IOBluetoothRFCOMMChannel?
                let result = self.device.openRFCOMMChannelAsync(
                    &opened, withChannelID: channelID, delegate: delegate)
                if result == kIOReturnSuccess, let opened {
                    self.lifecycle.attach(opened, generation: generation)
                } else {
                    self.lifecycle.discoveryFailed(
                        "控制通道忙（IOReturn \(result)）", generation: generation)
                }
            }
        }
    }

    func close() {
        // Invalidate before close(), which can itself cause delegate callbacks.
        let channel = lifecycle.close()
        channel?.close()
        channelDelegate = nil
    }

    @discardableResult
    func send(_ packet: [UInt8]) -> Bool {
        guard let channel = lifecycle.channel else { return false }
        return lifecycle.send(packet, mtu: Int(channel.getMTU())) { packet in
            trace(packet, direction: "TX")
            var bytes = packet
            // SDK success means buffered, not an earbud acknowledgement.
            let result = bytes.withUnsafeMutableBytes { raw in
                channel.writeAsync(raw.baseAddress, length: UInt16(raw.count), refcon: nil)
            }
            return result == kIOReturnSuccess ? nil : "写入失败（IOReturn \(result)）"
        }
    }

    // An SDK channel object may be reused. Each delegate retains the opening's token,
    // so queued callbacks cannot inherit a newer connection's generation.
    private final class ChannelDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
        private weak var owner: RFCOMMTransport?
        private let generation: Int

        init(owner: RFCOMMTransport, generation: Int) {
            self.owner = owner
            self.generation = generation
        }

        private func deliver(_ callback: @escaping (RFCOMMTransport) -> Void) {
            DispatchQueue.main.async { [weak owner, generation] in
                guard let owner else { return }
                owner.lifecycle.deliver(generation: generation) { callback(owner) }
            }
        }

        func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
            guard let channel else { return }
            // Enqueue even callbacks during openRFCOMMChannelAsync, so attach runs first.
            deliver { owner in
                owner.lifecycle.opened(channel, error: error == kIOReturnSuccess
                    ? nil : "打开控制通道失败（IOReturn \(error)）")
            }
        }

        func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!,
                               data dataPointer: UnsafeMutableRawPointer!,
                               length dataLength: Int) {
            guard let channel, let dataPointer, dataLength > 0 else { return }
            // Consume the SDK data pointer inside the callback, before dispatch.
            let chunk = Array(UnsafeBufferPointer(
                start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
            deliver { owner in
                guard owner.lifecycle.acceptsData(from: channel) else { return }
                owner.trace(chunk, direction: "RX")
                owner.lifecycle.received(chunk, from: channel)
            }
        }

        func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
            guard let channel else { return }
            deliver { $0.lifecycle.closed(channel) }
        }

        func rfcommChannelWriteComplete(_ channel: IOBluetoothRFCOMMChannel!,
                                        refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
            guard let channel else { return }
            deliver { owner in
                owner.lifecycle.writeCompleted(channel, error: error == kIOReturnSuccess
                    ? nil : "异步写入失败（IOReturn \(error)）")
            }
        }
    }

    private func trace(_ bytes: [UInt8], direction: String) {
        guard tracing else { return }
        let line = RFCOMMTraceFormatter.line(
            bytes, timestamp: Date().ISO8601Format(), generation: lifecycle.generation,
            direction: direction, includeRaw: rawTracing)
        AppLogger.transport.debug("\(line, privacy: .public)")
    }
}
