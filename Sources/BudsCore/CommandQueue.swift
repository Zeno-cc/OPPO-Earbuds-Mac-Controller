import Foundation

public struct PendingCommand {
    public typealias ResponseMatcher = (BudsProtocol.Frame) -> Bool

    public let packet: [UInt8]
    public let sequence: UInt8
    public let timeout: TimeInterval
    public let retryLimit: Int
    let responseMatcher: ResponseMatcher

    public init(packet: [UInt8],
                sequence: UInt8,
                timeout: TimeInterval = 1,
                retryLimit: Int = 1,
                responseMatcher: @escaping ResponseMatcher) {
        self.packet = packet
        self.sequence = sequence
        self.timeout = timeout
        self.retryLimit = retryLimit
        self.responseMatcher = responseMatcher
    }
}

public enum QueryCommandFailure: Equatable {
    case sendFailed
    case timedOut
    case cancelled
}

public enum QueryCommandResult {
    case success(BudsProtocol.Frame)
    case failure(QueryCommandFailure)
}

/// Serialises query commands without making assumptions about any device-specific opcode.
/// Concrete query packets and response matchers are supplied only after protocol capture.
public final class CommandQueue {
    public typealias Completion = (QueryCommandResult) -> Void
    public typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    private struct QueuedQuery {
        let id: UInt64
        let command: PendingCommand
        let completion: Completion
        var attempts = 0
    }

    private let transport: any ControlTransport
    private let pacing: TimeInterval
    private let schedule: Scheduler
    private var encoder = OPOPacketEncoder()
    private var waiting: [QueuedQuery] = []
    private var active: QueuedQuery?
    private var isPacing = false
    private var nextID: UInt64 = 0

    public convenience init(transport: any ControlTransport,
                            pacing: TimeInterval = 0.2) {
        self.init(transport: transport, pacing: pacing) { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    }

    public init(transport: any ControlTransport,
                pacing: TimeInterval = 0.2,
                scheduler: @escaping Scheduler) {
        self.transport = transport
        self.pacing = pacing
        self.schedule = scheduler
    }

    public var hasPendingQuery: Bool {
        active != nil || !waiting.isEmpty
    }

    @discardableResult
    public func sendHello() -> Bool {
        transport.send(encoder.encodeHello())
    }

    /// Set commands deliberately bypass query retry. A repeated hardware write can apply
    /// the same user action twice, so its device report remains the only confirmation.
    @discardableResult
    public func setNoiseMode(_ mode: NoiseMode, level: ANCLevel?,
                             profile: BudsProtocol.Profile) -> Bool {
        guard let packet = encoder.encodeSetNoiseMode(mode, level: level, profile: profile)
        else { return false }
        return transport.send(packet)
    }

    @discardableResult
    public func setEqualizer(_ preset: EQPreset,
                             profile: BudsProtocol.Profile) -> Bool {
        guard let packet = encoder.encodeSetEqualizer(preset, profile: profile) else {
            return false
        }
        return transport.send(packet)
    }

    @discardableResult
    public func setGameMode(_ enabled: Bool,
                            profile: BudsProtocol.Profile) -> Bool {
        guard let packet = encoder.encodeSetGameMode(enabled, profile: profile) else {
            return false
        }
        return transport.send(packet)
    }

    /// Enqueues the Air5 read-only battery request using the same sequence stream as the
    /// handshake and matches only the corresponding response for this request.
    @discardableResult
    public func enqueueBatteryQuery(
        profile: BudsProtocol.Profile,
        timeout: TimeInterval = 1,
        completion: @escaping Completion
    ) -> Bool {
        guard let packet = encoder.encodeBatteryQuery(profile: profile) else { return false }
        let sequence = encoder.sequence
        enqueue(PendingCommand(
            packet: packet,
            sequence: sequence,
            timeout: timeout,
            retryLimit: 1,
            responseMatcher: {
                $0.opcode == BudsProtocol.opcodeBatteryResponse
                    && $0.sequence == sequence
            }), completion: completion)
        return true
    }

    @discardableResult
    public func enqueueDeviceInformationQuery(
        profile: BudsProtocol.Profile,
        timeout: TimeInterval = 1,
        completion: @escaping Completion
    ) -> Bool {
        guard let packet = encoder.encodeDeviceInformationQuery(profile: profile) else {
            return false
        }
        let sequence = encoder.sequence
        enqueue(PendingCommand(
            packet: packet,
            sequence: sequence,
            timeout: timeout,
            retryLimit: 1,
            responseMatcher: {
                $0.opcode == BudsProtocol.opcodeDeviceInformationResponse
                    && $0.sequence == sequence
            }), completion: completion)
        return true
    }

    @discardableResult
    public func enqueueEqualizerQuery(
        profile: BudsProtocol.Profile,
        timeout: TimeInterval = 1,
        completion: @escaping Completion
    ) -> Bool {
        guard let packet = encoder.encodeEqualizerQuery(profile: profile) else { return false }
        let sequence = encoder.sequence
        enqueue(PendingCommand(
            packet: packet,
            sequence: sequence,
            timeout: timeout,
            retryLimit: 1,
            responseMatcher: {
                $0.opcode == BudsProtocol.opcodeEqualizerResponse
                    && $0.sequence == sequence
            }), completion: completion)
        return true
    }

    @discardableResult
    public func enqueueGameModeQuery(
        profile: BudsProtocol.Profile,
        timeout: TimeInterval = 1,
        completion: @escaping Completion
    ) -> Bool {
        guard let packet = encoder.encodeGameModeQuery(profile: profile) else { return false }
        let sequence = encoder.sequence
        enqueue(PendingCommand(
            packet: packet,
            sequence: sequence,
            timeout: timeout,
            retryLimit: 1,
            responseMatcher: {
                $0.opcode == BudsProtocol.opcodeGameModeResponse
                    && $0.sequence == sequence
            }), completion: completion)
        return true
    }

    public func enqueue(_ command: PendingCommand,
                        completion: @escaping Completion) {
        nextID &+= 1
        waiting.append(QueuedQuery(
            id: nextID, command: command, completion: completion))
        startNextIfPossible()
    }

    /// Returns true only when the frame completed the active query. Callers must still
    /// reduce every frame into session state so unsolicited reports are never discarded.
    @discardableResult
    public func receive(_ frame: BudsProtocol.Frame) -> Bool {
        guard let active, active.command.responseMatcher(frame) else { return false }
        finishActive(with: .success(frame))
        return true
    }

    public func cancelAll() {
        let cancelled = ([active].compactMap { $0 } + waiting)
        active = nil
        waiting.removeAll()
        isPacing = false
        for query in cancelled {
            query.completion(.failure(.cancelled))
        }
    }

    private func startNextIfPossible() {
        guard active == nil, !isPacing, !waiting.isEmpty else { return }
        active = waiting.removeFirst()
        sendActive()
    }

    private func sendActive() {
        guard var query = active else { return }
        query.attempts += 1
        active = query

        guard transport.send(query.command.packet) else {
            finishActive(with: .failure(.sendFailed))
            return
        }

        let id = query.id
        let attempt = query.attempts
        schedule(query.command.timeout) { [weak self] in
            self?.timeoutQuery(id: id, attempt: attempt)
        }
    }

    private func timeoutQuery(id: UInt64, attempt: Int) {
        guard let query = active, query.id == id, query.attempts == attempt else { return }
        guard query.attempts <= query.command.retryLimit else {
            finishActive(with: .failure(.timedOut))
            return
        }

        schedule(pacing) { [weak self] in
            guard let self, self.active?.id == id,
                  self.active?.attempts == attempt else { return }
            self.sendActive()
        }
    }

    private func finishActive(with result: QueryCommandResult) {
        guard let query = active else { return }
        active = nil
        // Set the gate before invoking client code. A completion may enqueue the next
        // query synchronously, and it must not bypass the pacing interval by re-entry.
        isPacing = true
        query.completion(result)

        schedule(pacing) { [weak self] in
            guard let self else { return }
            self.isPacing = false
            self.startNextIfPossible()
        }
    }
}
