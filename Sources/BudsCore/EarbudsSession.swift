import Foundation

public typealias EarbudsBatteryState = BatteryState

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
    public var batteryFeature: FeatureState<BatteryState> = .unknown
    public var deviceInformationFeature: FeatureState<DeviceInformation> = .unknown
    public var equalizerFeature: FeatureState<EQPreset> = .unknown
    public var gameModeFeature: FeatureState<Bool> = .unknown
    public var placement = EarbudsPlacementState()
    public var mode: NoiseMode?
    public var ancLevel: ANCLevel?
    public var pendingMode: NoiseMode?
    public var pendingANCLevel: ANCLevel?
    public var pendingEqualizer: EQPreset?
    public var pendingGameMode: Bool?

    public init() {}
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
    private var initialSyncWorkItem: DispatchWorkItem?

    public init(profile: BudsProtocol.Profile, transport: any ControlTransport,
                initialState: EarbudsState = EarbudsState()) {
        self.profile = profile
        self.transport = transport
        self.commands = CommandQueue(transport: transport)
        self.state = initialState
        if !profile.capabilities.contains(.deviceInformation) {
            self.state.deviceInformationFeature = .unsupported
        }
        if !profile.capabilities.contains(.equalizer) {
            self.state.equalizerFeature = .unsupported
        }
        if !profile.capabilities.contains(.gameMode) {
            self.state.gameModeFeature = .unsupported
        }
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
        initialSyncWorkItem?.cancel()
        initialSyncWorkItem = nil
        commands.cancelAll()
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

    @discardableResult
    public func set(equalizer preset: EQPreset) -> Bool {
        guard connectionState == .ready, profile.capabilities.contains(.equalizer),
              commands.setEqualizer(preset, profile: profile)
        else { return false }
        state.pendingEqualizer = preset
        onStateChange?()
        // Air5 normally reports `04 05` immediately. The read-back also confirms the
        // setting if that report was consumed by the phone's simultaneous connection.
        _ = queryEqualizer(confirmingPendingWrite: true)
        return true
    }

    @discardableResult
    public func set(gameMode enabled: Bool) -> Bool {
        guard connectionState == .ready, profile.capabilities.contains(.gameMode),
              commands.setGameMode(enabled, profile: profile)
        else { return false }
        state.pendingGameMode = enabled
        onStateChange?()
        // The switch-feature command has an acknowledgement but no preference report,
        // so the state shown to the user comes from a verified query read-back.
        _ = queryGameMode(confirmingPendingWrite: true)
        return true
    }

    @discardableResult
    public func enqueueQuery(_ command: PendingCommand,
                             decodeResponse: @escaping (BudsProtocol.Frame)
                                 -> [BudsProtocol.Update] = { _ in [] },
                             completion: @escaping CommandQueue.Completion) -> Bool {
        guard connectionState == .ready else { return false }
        commands.enqueue(command) { [weak self] result in
            if case .success(let frame) = result {
                self?.apply(decodeResponse(frame))
            }
            completion(result)
        }
        return true
    }

    @discardableResult
    public func retryBatterySync() -> Bool {
        guard connectionState == .ready,
              profile.capabilities.contains(.activeBatteryQuery)
        else { return false }
        let interruptedInitialSync = initialSyncWorkItem != nil
        initialSyncWorkItem?.cancel()
        initialSyncWorkItem = nil
        let enqueued = queryBattery()
        if interruptedInitialSync,
           profile.initialSyncPlan.contains(.deviceInformation) {
            _ = queryDeviceInformation()
        }
        if interruptedInitialSync, profile.initialSyncPlan.contains(.equalizer) {
            _ = queryEqualizer()
        }
        if interruptedInitialSync, profile.initialSyncPlan.contains(.gameMode) {
            _ = queryGameMode()
        }
        return enqueued
    }

    @discardableResult
    public func retryDeviceInformationSync() -> Bool {
        guard connectionState == .ready,
              profile.capabilities.contains(.deviceInformation)
        else { return false }
        let interruptedInitialSync = initialSyncWorkItem != nil
        initialSyncWorkItem?.cancel()
        initialSyncWorkItem = nil
        if interruptedInitialSync,
           profile.initialSyncPlan.contains(.battery) {
            _ = queryBattery()
        }
        let enqueued = queryDeviceInformation()
        if interruptedInitialSync, profile.initialSyncPlan.contains(.equalizer) {
            _ = queryEqualizer()
        }
        if interruptedInitialSync, profile.initialSyncPlan.contains(.gameMode) {
            _ = queryGameMode()
        }
        return enqueued
    }

    /// Refreshes both user-facing sound settings. If the initial sync is about to run,
    /// leave it intact instead of adding duplicate requests to the serial queue.
    @discardableResult
    public func refreshSoundFeatures() -> Bool {
        guard connectionState == .ready else { return false }
        if initialSyncWorkItem != nil { return true }
        let equalizerQueued = queryEqualizer()
        let gameModeQueued = queryGameMode()
        return equalizerQueued || gameModeQueued
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
                scheduleInitialSync()
            } else {
                connectionState = .failed(.handshakeFailed)
            }
            onStateChange?()

        case .bytes(let chunk):
            onActivity?()
            receiveBuffer.append(contentsOf: chunk)
            for frame in BudsProtocol.drainFrames(from: &receiveBuffer) {
                commands.receive(frame)
                apply(BudsProtocol.interpret(frame, profile: profile))
            }

        case .closed:
            initialSyncWorkItem?.cancel()
            initialSyncWorkItem = nil
            commands.cancelAll()
            receiveBuffer.removeAll()
            connectionState = .idle
            onStateChange?()

        case .failed(let error):
            initialSyncWorkItem?.cancel()
            initialSyncWorkItem = nil
            commands.cancelAll()
            connectionState = .failed(.transport(error))
            onStateChange?()
        }
    }

    private func apply(
        _ updates: [BudsProtocol.Update],
        confirmingEqualizerWrite: Bool = false,
        confirmingGameModeWrite: Bool = false
    ) {
        guard !updates.isEmpty else { return }
        var receivedBattery = false
        for update in updates {
            switch update {
            case .noiseMode(let mode):
                state.mode = mode
                state.pendingMode = nil
            case .ancLevel(let level):
                state.ancLevel = level
                state.pendingANCLevel = nil
            case .battery(let slot, let reading):
                receivedBattery = true
                switch slot {
                case .left:
                    state.battery.left = reading
                case .right:
                    state.battery.right = reading
                case .enclosure:
                    state.battery.enclosure = reading
                }
            case .placement(let slot, let placement):
                let changed = state.placement[slot] != placement
                state.placement[slot] = placement
                if changed, placement == .inCase {
                    switch slot {
                    case .left:
                        // Preserve an explicit charging reading that arrived just before
                        // the placement report. Otherwise clear the stale out-of-case value.
                        if state.battery.left?.isCharging != true {
                            state.battery.left = nil
                        }
                    case .right:
                        if state.battery.right?.isCharging != true {
                            state.battery.right = nil
                        }
                    case .enclosure: break
                    }
                }
            case .deviceInformation(let information):
                state.deviceInformationFeature = .ready(information)
            case .equalizer(let preset):
                state.equalizerFeature = .ready(preset)
                if confirmingEqualizerWrite || state.pendingEqualizer == preset {
                    state.pendingEqualizer = nil
                }
            case .gameMode(let enabled):
                state.gameModeFeature = .ready(enabled)
                if confirmingGameModeWrite || state.pendingGameMode == enabled {
                    state.pendingGameMode = nil
                }
            }
        }
        if receivedBattery {
            state.batteryFeature = .ready(state.battery)
        }
        onStateChange?()
    }

    private func scheduleInitialSync() {
        let plan = profile.initialSyncPlan
        guard !plan.isEmpty else { return }
        if plan.contains(.battery) { state.batteryFeature = .loading }
        if plan.contains(.deviceInformation) {
            switch state.deviceInformationFeature {
            case .ready:
                // Keep the last verified version visible while the control channel refreshes it.
                break
            default:
                state.deviceInformationFeature = .loading
            }
        }
        if plan.contains(.equalizer), case .ready = state.equalizerFeature {
            // Keep the last confirmed preset visible while it refreshes.
        } else if plan.contains(.equalizer) {
            state.equalizerFeature = .loading
        }
        if plan.contains(.gameMode), case .ready = state.gameModeFeature {
            // Keep the last confirmed switch state visible while it refreshes.
        } else if plan.contains(.gameMode) {
            state.gameModeFeature = .loading
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .ready else { return }
            self.initialSyncWorkItem = nil
            if plan.contains(.battery) { self.queryBattery() }
            if plan.contains(.deviceInformation) { self.queryDeviceInformation() }
            if plan.contains(.equalizer) { self.queryEqualizer() }
            if plan.contains(.gameMode) { self.queryGameMode() }
        }
        initialSyncWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @discardableResult
    private func queryBattery() -> Bool {
        state.batteryFeature = .loading
        onStateChange?()
        guard commands.enqueueBatteryQuery(
            profile: profile,
            completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                let updates = BudsProtocol.interpretBatteryResponse(frame, profile: self.profile)
                if updates.isEmpty {
                    self.state.batteryFeature = .failed("电量响应格式异常")
                    self.onStateChange?()
                } else {
                    self.apply(updates)
                }
            case .failure(.cancelled):
                return
            case .failure:
                if case .ready = self.state.batteryFeature {
                    return
                }
                self.state.batteryFeature = .failed("读取电量失败")
                self.onStateChange?()
            }
        }) else {
            state.batteryFeature = .unsupported
            onStateChange?()
            return false
        }
        return true
    }

    @discardableResult
    private func queryDeviceInformation() -> Bool {
        switch state.deviceInformationFeature {
        case .ready:
            // A refresh should not hide information already obtained from this device.
            break
        default:
            state.deviceInformationFeature = .loading
            onStateChange?()
        }
        guard commands.enqueueDeviceInformationQuery(
            profile: profile,
            completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                let updates = BudsProtocol.interpretDeviceInformationResponse(
                    frame, profile: self.profile)
                if updates.isEmpty {
                    if case .ready = self.state.deviceInformationFeature { return }
                    self.state.deviceInformationFeature = .failed("设备信息响应格式异常")
                    self.onStateChange?()
                } else {
                    self.apply(updates)
                }
            case .failure(.cancelled):
                return
            case .failure:
                if case .ready = self.state.deviceInformationFeature { return }
                self.state.deviceInformationFeature = .failed("读取设备信息失败")
                self.onStateChange?()
            }
        }) else {
            state.deviceInformationFeature = .unsupported
            onStateChange?()
            return false
        }
        return true
    }

    @discardableResult
    private func queryEqualizer(confirmingPendingWrite: Bool = false) -> Bool {
        switch state.equalizerFeature {
        case .ready:
            break
        default:
            state.equalizerFeature = .loading
            onStateChange?()
        }
        guard commands.enqueueEqualizerQuery(
            profile: profile,
            completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                let updates = BudsProtocol.interpretEqualizerResponse(
                    frame, profile: self.profile)
                if updates.isEmpty {
                    if confirmingPendingWrite { self.state.pendingEqualizer = nil }
                    if case .ready = self.state.equalizerFeature {
                        self.onStateChange?()
                        return
                    }
                    self.state.equalizerFeature = .failed("均衡器响应格式异常")
                    self.onStateChange?()
                } else {
                    self.apply(updates, confirmingEqualizerWrite: confirmingPendingWrite)
                }
            case .failure(.cancelled):
                return
            case .failure:
                if confirmingPendingWrite { self.state.pendingEqualizer = nil }
                if case .ready = self.state.equalizerFeature {
                    self.onStateChange?()
                    return
                }
                self.state.equalizerFeature = .failed("读取均衡器失败")
                self.onStateChange?()
            }
        }) else {
            state.equalizerFeature = .unsupported
            state.pendingEqualizer = nil
            onStateChange?()
            return false
        }
        return true
    }

    @discardableResult
    private func queryGameMode(confirmingPendingWrite: Bool = false) -> Bool {
        switch state.gameModeFeature {
        case .ready:
            break
        default:
            state.gameModeFeature = .loading
            onStateChange?()
        }
        guard commands.enqueueGameModeQuery(
            profile: profile,
            completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                let updates = BudsProtocol.interpretGameModeResponse(
                    frame, profile: self.profile)
                if updates.isEmpty {
                    if confirmingPendingWrite { self.state.pendingGameMode = nil }
                    if case .ready = self.state.gameModeFeature {
                        self.onStateChange?()
                        return
                    }
                    self.state.gameModeFeature = .failed("游戏模式响应格式异常")
                    self.onStateChange?()
                } else {
                    self.apply(updates, confirmingGameModeWrite: confirmingPendingWrite)
                }
            case .failure(.cancelled):
                return
            case .failure:
                if confirmingPendingWrite { self.state.pendingGameMode = nil }
                if case .ready = self.state.gameModeFeature {
                    self.onStateChange?()
                    return
                }
                self.state.gameModeFeature = .failed("读取游戏模式失败")
                self.onStateChange?()
            }
        }) else {
            state.gameModeFeature = .unsupported
            state.pendingGameMode = nil
            onStateChange?()
            return false
        }
        return true
    }
}
