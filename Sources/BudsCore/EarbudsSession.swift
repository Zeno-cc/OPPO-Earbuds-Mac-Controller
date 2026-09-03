import Foundation

public struct EarbudsBatteryState: Equatable {
    public var left: Int?
    public var right: Int?
    public var enclosure: Int?
    public var combined: Int?

    public init(left: Int? = nil, right: Int? = nil,
                enclosure: Int? = nil, combined: Int? = nil) {
        self.left = left
        self.right = right
        self.enclosure = enclosure
        self.combined = combined
    }
}

public struct EarbudsPlacementState: Equatable {
    public var left: BudsProtocol.BudPlacement?
    public var right: BudsProtocol.BudPlacement?

    public init(left: BudsProtocol.BudPlacement? = nil,
                right: BudsProtocol.BudPlacement? = nil) {
        self.left = left
        self.right = right
    }

    public subscript(slot: BudsProtocol.BatterySlot) -> BudsProtocol.BudPlacement? {
        get { slot == .left ? left : slot == .right ? right : nil }
        set {
            switch slot {
            case .left: left = newValue
            case .right: right = newValue
            case .enclosure: break
            }
        }
    }
}

public struct EarbudsState: Equatable {
    public var battery = EarbudsBatteryState()
    public var placement = EarbudsPlacementState()
    public var mode: NoiseMode?
    public var ancLevel: ANCLevel?
    public var pendingMode: NoiseMode?
    public var pendingANCLevel: ANCLevel?

    public init() {}
}

public final class CommandQueue {
    private let transport: any ControlTransport
    private var encoder = OPOPacketEncoder()

    public init(transport: any ControlTransport) {
        self.transport = transport
    }

    @discardableResult
    public func sendHello() -> Bool {
        transport.send(encoder.encodeHello())
    }

    @discardableResult
    public func setNoiseMode(_ mode: NoiseMode, level: ANCLevel?,
                             profile: BudsProtocol.Profile) -> Bool {
        guard let packet = encoder.encodeSetNoiseMode(mode, level: level, profile: profile)
        else { return false }
        // Set commands are intentionally written once. A later device report is the only
        // success signal; blindly retrying a write could toggle hardware twice.
        return transport.send(packet)
    }
}

public final class EarbudsSession {
    public let profile: BudsProtocol.Profile
    public private(set) var connectionState: SessionState = .idle
    public private(set) var intent: ConnectionIntent = .automatic
    public private(set) var state = EarbudsState()

    public var onStateChange: (() -> Void)?
    public var onActivity: (() -> Void)?

    private let transport: any ControlTransport
    private let commands: CommandQueue
    private var receiveBuffer: [UInt8] = []

    public init(profile: BudsProtocol.Profile, transport: any ControlTransport,
                initialState: EarbudsState = EarbudsState()) {
        self.profile = profile
        self.transport = transport
        self.commands = CommandQueue(transport: transport)
        self.state = initialState
        transport.eventHandler = { [weak self] event in self?.handle(event) }
    }

    public func open(intent: ConnectionIntent = .automatic) {
        self.intent = intent
        guard connectionState == .idle || isFailed else { return }
        connectionState = .openingControlChannel
        onStateChange?()
        transport.open()
    }

    public func close(intent: ConnectionIntent = .disconnectedByUser) {
        self.intent = intent
        connectionState = .disconnecting
        onStateChange?()
        transport.close()
        receiveBuffer.removeAll()
        connectionState = .idle
        onStateChange?()
    }

    @discardableResult
    public func set(mode: NoiseMode, rememberedLevel: ANCLevel? = nil) -> Bool {
        guard connectionState == .ready, profile.capabilities.contains(.noiseControl)
        else { return false }
        let level = profile == .t500Pro ? rememberedLevel : nil
        guard commands.setNoiseMode(mode, level: level, profile: profile) else { return false }
        state.pendingMode = mode
        onStateChange?()
        return true
    }

    @discardableResult
    public func set(ancLevel: ANCLevel) -> Bool {
        guard connectionState == .ready, profile.capabilities.contains(.ancLevels),
              commands.setNoiseMode(.noiseCancellation, level: ancLevel, profile: profile)
        else { return false }
        state.pendingMode = .noiseCancellation
        state.pendingANCLevel = ancLevel
        onStateChange?()
        return true
    }

    private var isFailed: Bool {
        if case .failed = connectionState { return true }
        return false
    }

    private func handle(_ event: ControlTransportEvent) {
        switch event {
        case .opened:
            connectionState = .handshaking
            onStateChange?()
            if commands.sendHello() {
                connectionState = .ready
            } else {
                connectionState = .failed(.handshakeFailed)
            }
            onStateChange?()

        case .bytes(let chunk):
            onActivity?()
            receiveBuffer.append(contentsOf: chunk)
            for frame in BudsProtocol.drainFrames(from: &receiveBuffer) {
                apply(BudsProtocol.interpret(frame, profile: profile))
            }

        case .closed:
            receiveBuffer.removeAll()
            connectionState = .idle
            onStateChange?()

        case .failed(let error):
            connectionState = .failed(.transport(error))
            onStateChange?()
        }
    }

    private func apply(_ updates: [BudsProtocol.Update]) {
        guard !updates.isEmpty else { return }
        for update in updates {
            switch update {
            case .noiseMode(let mode):
                state.mode = mode
                state.pendingMode = nil
            case .ancLevel(let level):
                state.ancLevel = level
                state.pendingANCLevel = nil
            case .battery(let slot, let level):
                switch slot {
                case .left: state.battery.left = level
                case .right: state.battery.right = level
                case .enclosure: state.battery.enclosure = level
                }
            case .placement(let slot, let placement):
                let changed = state.placement[slot] != placement
                state.placement[slot] = placement
                if changed, placement == .inCase {
                    switch slot {
                    case .left: state.battery.left = nil
                    case .right: state.battery.right = nil
                    case .enclosure: break
                    }
                }
            }
        }
        onStateChange?()
    }
}
