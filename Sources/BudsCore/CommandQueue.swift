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

public enum WriteDispatchResult: Equatable {
    case sent
    case failed
    case cancelled
}

/// Paces queries and single-send writes; only captured query/response pairs are used.
public final class CommandQueue {
    public typealias Completion = (QueryCommandResult) -> Void
    public typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    private struct QueuedQuery {
        let id: UInt64
        let command: PendingCommand
        var completion: Completion
        var writeCompletion: ((WriteDispatchResult) -> Void)? = nil
        var urgent = false
        var coalescingKey: UInt16? = nil
        var writeEpoch: UInt64 = 0
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
    private var generation: UInt64 = 0
    private var writeEpoch: UInt64 = 0
    private var urgentBurst = 0

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

    /// True means accepted into the send lane, not delivered or confirmed by the device.
    /// Writes share pacing with reads and are never retried.
    @discardableResult
    public func setNoiseMode(_ mode: NoiseMode, level: ANCLevel?,
                             profile: BudsProtocol.Profile,
                             dispatched: @escaping (WriteDispatchResult) -> Void = { _ in }) -> Bool {
        guard let packet = encoder.encodeSetNoiseMode(mode, level: level, profile: profile)
        else { return false }
        return enqueueWrite(packet, dispatched: dispatched)
    }

    @discardableResult
    public func setEqualizer(_ preset: EQPreset,
                             profile: BudsProtocol.Profile,
                             dispatched: @escaping (WriteDispatchResult) -> Void = { _ in }) -> Bool {
        guard let packet = encoder.encodeSetEqualizer(preset, profile: profile) else {
            return false
        }
        return enqueueWrite(packet, dispatched: dispatched)
    }

    @discardableResult
    public func setGameMode(_ enabled: Bool,
                            profile: BudsProtocol.Profile,
                            dispatched: @escaping (WriteDispatchResult) -> Void = { _ in }) -> Bool {
        guard let packet = encoder.encodeSetGameMode(enabled, profile: profile) else {
            return false
        }
        return enqueueWrite(packet, dispatched: dispatched)
    }

    private func enqueueWrite(_ packet: [UInt8],
                              dispatched: @escaping (WriteDispatchResult) -> Void) -> Bool {
        guard transport.isOpen else { return false }
        writeEpoch &+= 1
        nextID &+= 1
        waiting.append(QueuedQuery(id: nextID,
            command: PendingCommand(packet: packet, sequence: encoder.sequence,
                                    retryLimit: 0, responseMatcher: { _ in false }),
            completion: { _ in }, writeCompletion: dispatched, urgent: true))
        startNextIfPossible()
        return true
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
            }), coalescingKey: 0x0601, completion: completion)
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
            }), coalescingKey: 0x0501, completion: completion)
        return true
    }

    @discardableResult
    public func enqueueEqualizerQuery(
        profile: BudsProtocol.Profile,
        timeout: TimeInterval = 1,
        verification: Bool = false,
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
            }), urgent: verification, coalescingKey: verification ? nil : 0x0f01,
            completion: completion)
        return true
    }

    @discardableResult
    public func enqueueGameModeQuery(
        profile: BudsProtocol.Profile,
        timeout: TimeInterval = 1,
        verification: Bool = false,
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
            }), urgent: verification, coalescingKey: verification ? nil : 0x0d01,
            completion: completion)
        return true
    }

    public func enqueue(_ command: PendingCommand,
                        urgent: Bool = false,
                        coalescingKey: UInt16? = nil,
                        completion: @escaping Completion) {
        if let key = coalescingKey {
            if let current = active, current.coalescingKey == key,
               current.writeEpoch == writeEpoch {
                let earlier = current.completion
                active?.completion = { earlier($0); completion($0) }
                return
            }
            if let index = waiting.firstIndex(where: {
                $0.coalescingKey == key && $0.writeEpoch == writeEpoch
            }) {
                let earlier = waiting[index].completion
                waiting[index].completion = { earlier($0); completion($0) }
                return
            }
        }
        nextID &+= 1
        waiting.append(QueuedQuery(
            id: nextID, command: command, completion: completion,
            urgent: urgent, coalescingKey: coalescingKey, writeEpoch: writeEpoch))
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
        generation &+= 1
        let cancelled = ([active].compactMap { $0 } + waiting)
        active = nil
        waiting.removeAll()
        isPacing = false
        urgentBurst = 0
        for query in cancelled {
            if let dispatched = query.writeCompletion {
                dispatched(.cancelled)
            } else {
                query.completion(.failure(.cancelled))
            }
        }
    }

    public func setCustomEqualizer(_ curve: CustomEqualizer, action: CustomEQAction = .update,
                                   dispatched: @escaping (WriteDispatchResult) -> Void) -> Bool {
        guard let packet = encoder.encodeSetCustomEqualizer(curve, action: action) else { return false }
        return enqueueWrite(packet, dispatched: dispatched)
    }

    public func enqueueCustomEqualizerQuery(verification: Bool = false, completion: @escaping Completion) {
        let packet = encoder.encodeCustomEqualizerQuery()
        let sequence = encoder.sequence
        enqueue(PendingCommand(packet: packet, sequence: sequence, retryLimit: 1,
            responseMatcher: { $0.opcode == 0x2281 && $0.sequence == sequence }),
            urgent: verification, coalescingKey: verification ? nil : 0x2201, completion: completion)
    }

    private func startNextIfPossible() {
        guard active == nil, !isPacing, !waiting.isEmpty else { return }
        let urgentIndex = waiting.firstIndex(where: { $0.urgent })
        let backgroundIndex = waiting.firstIndex(where: { !$0.urgent })
        guard let index = urgentBurst < 3 ? (urgentIndex ?? backgroundIndex)
            : (backgroundIndex ?? urgentIndex) else { return }
        active = waiting.remove(at: index)
        urgentBurst = active?.urgent == true ? urgentBurst + 1 : 0
        sendActive()
    }

    private func sendActive() {
        guard var query = active else { return }
        query.attempts += 1
        active = query

        let sent = transport.send(query.command.packet)
        // A transport failure can synchronously cancel the entire lane.
        guard active?.id == query.id else { return }
        if let dispatched = query.writeCompletion {
            active = nil
            beginPacing { dispatched(sent ? .sent : .failed) }
            return
        }
        guard sent else {
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
        beginPacing { query.completion(result) }
    }

    private func beginPacing(_ completion: () -> Void) {
        // Set the gate before invoking client code. A completion may enqueue the next
        // query synchronously, and it must not bypass the pacing interval by re-entry.
        isPacing = true
        let generation = self.generation
        completion()

        schedule(pacing) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.isPacing = false
            self.startNextIfPossible()
        }
    }
}
