import Foundation

public struct TransportError: Error, Equatable {
    public let message: String

    public init(_ message: String) { self.message = message }
}

public enum SessionError: Error, Equatable {
    case transport(TransportError)
    case handshakeFailed

    public var message: String {
        switch self {
        case .transport(let error): return error.message
        case .handshakeFailed: return "发送握手失败"
        }
    }
}

public enum ControlTransportEvent: Equatable {
    case opened
    case bytes([UInt8])
    case closed
    case failed(TransportError)
}

public protocol ControlTransport: AnyObject {
    var eventHandler: ((ControlTransportEvent) -> Void)? { get set }
    var isOpen: Bool { get }

    func open()
    func close()
    @discardableResult func send(_ bytes: [UInt8]) -> Bool
}

public enum SessionState: Equatable {
    case idle
    case connecting
    case basebandConnected
    case openingControlChannel
    case handshaking
    case syncing
    case ready
    case disconnecting
    case failed(SessionError)
}

public enum ConnectionIntent: Equatable {
    case automatic
    case connected
    case disconnectedByUser
}
