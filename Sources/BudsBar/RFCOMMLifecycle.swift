import BudsCore

// State transitions shared by the SDK adapter and hardware-free regression tests.
// The adapter serializes access on the main queue.
final class RFCOMMLifecycle<Channel: AnyObject> {
    var eventHandler: ((ControlTransportEvent) -> Void)?
    private(set) var channel: Channel?
    private(set) var isOpen = false
    private var isOpening = false
    private(set) var generation = 0

    func deliver(generation token: Int, _ callback: () -> Void) {
        guard token == generation else { return }
        callback()
    }

    func beginOpen() -> Int? {
        guard channel == nil, !isOpening else { return nil }
        generation += 1
        isOpening = true
        return generation
    }

    func acceptsDiscovery(_ token: Int) -> Bool {
        token == generation && isOpening && channel == nil
    }

    func attach(_ channel: Channel, generation token: Int) {
        guard acceptsDiscovery(token) else { return }
        self.channel = channel
    }

    func discoveryFailed(_ message: String, generation token: Int) {
        guard acceptsDiscovery(token) else { return }
        _ = close()
        eventHandler?(.failed(TransportError(message)))
    }

    func close() -> Channel? {
        generation += 1
        let old = channel
        channel = nil
        isOpening = false
        isOpen = false
        return old
    }

    func opened(_ channel: Channel, error: String?) {
        guard self.channel === channel, isOpening else { return }
        isOpening = false
        if let error {
            _ = close()
            eventHandler?(.failed(TransportError(error)))
            return
        }
        self.channel = channel
        isOpen = true
        eventHandler?(.opened)
    }

    func acceptsData(from channel: Channel) -> Bool {
        self.channel === channel && isOpen
    }

    func received(_ bytes: [UInt8], from channel: Channel) {
        guard acceptsData(from: channel) else { return }
        eventHandler?(.bytes(bytes))
    }

    func closed(_ channel: Channel) {
        guard self.channel === channel else { return }
        _ = close()
        eventHandler?(.closed)
    }

    func writeCompleted(_ channel: Channel, error: String?) {
        guard acceptsData(from: channel), let error else { return }
        eventHandler?(.failed(TransportError(error)))
    }

    func send(_ bytes: [UInt8], mtu: Int, write: ([UInt8]) -> String?) -> Bool {
        guard channel != nil, isOpen else { return false }
        guard !bytes.isEmpty, bytes.count <= Int(UInt16.max), bytes.count <= mtu else {
            eventHandler?(.failed(TransportError(
                "写入长度无效（\(bytes.count) 字节，MTU \(mtu)）")))
            return false
        }
        if let error = write(bytes) {
            eventHandler?(.failed(TransportError(error)))
            return false
        }
        return true
    }
}

enum RFCOMMTraceFormatter {
    static func line(_ bytes: [UInt8], timestamp: String, generation: Int,
                     direction: String, includeRaw: Bool) -> String {
        let metadata = "\(timestamp) generation=\(generation) direction=\(direction) length=\(bytes.count)"
        return includeRaw ? "\(metadata) hex=\(BudsProtocol.hex(bytes))" : metadata
    }
}
