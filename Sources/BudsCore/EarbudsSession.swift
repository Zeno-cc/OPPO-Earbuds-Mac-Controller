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
    public var batteryObservations: [BudsProtocol.BatterySlot: BatterySlotObservation] = [:]
    public var connectionGeneration: UInt64 = 0
    public var deviceInformationFeature: FeatureState<DeviceInformation> = .unknown
    public var equalizerFeature: FeatureState<EQPreset> = .unknown
    public var customEqualizerFeature: FeatureState<[CustomEqualizer]> = .unknown
    public var unknownEqualizerMode: UInt8?
    public var unknownPlacementValues: [BudsProtocol.BatterySlot: UInt8] = [:]
    public var gameModeFeature: FeatureState<Bool> = .unknown
    public var placement = EarbudsPlacementState()
    public var mode: NoiseMode?
    public var ancLevel: ANCLevel?
    public var pendingMode: NoiseMode?
    public var pendingANCLevel: ANCLevel?
    public var pendingEqualizer: EQPreset?
    public var pendingGameMode: Bool?
    public var operations: [ControlFeature: FeatureOperation] = [:]
    public var soundRefresh: [ControlFeature: FeatureRefreshState] = [:]

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
    private let schedule: CommandQueue.Scheduler
    private let now: () -> TimeInterval
    private var nextOperationID: UInt64 = 0
    private var connectionGeneration: UInt64 = 0
    private var differentObservations: Set<ControlFeature> = []

    public init(profile: BudsProtocol.Profile, transport: any ControlTransport,
                initialState: EarbudsState = EarbudsState(),
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                scheduler: @escaping CommandQueue.Scheduler = { delay, action in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
                }) {
        self.profile = profile
        self.transport = transport
        self.schedule = scheduler
        self.now = now
        self.commands = CommandQueue(transport: transport, scheduler: scheduler)
        self.state = initialState
        self.state.pendingMode = nil
        self.state.customEqualizerFeature = .unknown
        self.state.pendingANCLevel = nil
        self.state.pendingEqualizer = nil
        self.state.pendingGameMode = nil
        self.state.operations = [:]
        self.state.soundRefresh = [:]
        self.state.placement = EarbudsPlacementState()
        self.state.unknownPlacementValues = [:]
        self.state.batteryObservations = [:]
        self.state.connectionGeneration = connectionGeneration
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
        connectionGeneration &+= 1
        state.connectionGeneration = connectionGeneration
        state.batteryObservations = [:]
        connectionState = .openingControlChannel
        onStateChange?()
        transport.open()
    }

    @discardableResult
    public func refreshCustomEqualizer(confirmingPendingWrite: Bool = false) -> Bool {
        guard connectionState == .ready, profile == .encoAir5Pro else { return false }
        let readbackID = confirmingPendingWrite ? state.operations[.equalizer]?.id : nil
        state.customEqualizerFeature = .loading
        onStateChange?()
        commands.enqueueCustomEqualizerQuery(verification: confirmingPendingWrite) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                if let curves = CustomEqualizer.decodeList(frame.payload) {
                    self.state.customEqualizerFeature = .ready(curves)
                    if let selected = curves.first(where: \.isSelected) {
                        self.state.equalizerFeature = .unknown
                        self.state.unknownEqualizerMode = selected.id
                    }
                    if confirmingPendingWrite, let operation = self.state.operations[.equalizer] {
                        let matches: Bool
                        switch operation.target {
                        case .customEqualizer(let target):
                            matches = curves.contains { $0.id == target.id && $0.isSelected && $0.hasSameContent(as: target) }
                        case .customEQManagement(let action, let target, let previousIDs):
                            switch action {
                            case .create: matches = curves.contains { !previousIDs.contains($0.id) && $0.hasSameContent(as: target) }
                            case .update: matches = curves.contains { $0.id == target.id && $0.isSelected && $0.hasSameContent(as: target) }
                            case .delete: matches = !curves.contains { $0.id == target.id }
                            }
                        default: matches = false
                        }
                        self.observe(.equalizer, matches: matches, readbackID: readbackID, isReadback: true)
                    }
                } else {
                    self.state.customEqualizerFeature = .failed("暂不支持这份自定义曲线数据")
                }
            case .failure(.cancelled): self.state.customEqualizerFeature = .unknown
            case .failure: self.state.customEqualizerFeature = .failed("读取自定义曲线失败")
            }
            self.onStateChange?()
        }
        return true
    }

    @discardableResult
    public func set(customEqualizer baseline: CustomEqualizer, gains: [Int8]) -> Bool {
        guard customEqualizerRejection(baseline, gains: gains) == nil,
              let target = baseline.replacingGains(gains) else { return false }
        let id = beginOperation(.equalizer, target: .customEqualizer(target))
        return acceptDispatch(.equalizer, id: id, accepted: commands.setCustomEqualizer(
            target, dispatched: dispatchHandler(.equalizer, id: id)))
    }

    public func customEqualizerRejection(_ baseline: CustomEqualizer, gains: [Int8]) -> String? {
        guard connectionState == .ready else { return "控制连接未就绪，请等待连接完成" }
        guard profile == .encoAir5Pro else { return "当前型号不支持自定义 EQ 写入" }
        guard state.operations[.equalizer]?.phase.isPending != true else {
            return "上一项 EQ 操作尚未结束，请稍候"
        }
        guard case .ready(let curves) = state.customEqualizerFeature, curves.contains(baseline) else {
            return "耳机曲线已变化或尚未读完，请重新读取并核对草稿"
        }
        guard let target = baseline.replacingGains(gains) else {
            return "需要 10 个频段，每段必须在 −6～+6 dB 内"
        }
        guard target.writePayload != nil else {
            let format = baseline.prefix.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "当前曲线格式尚未验证写入（前缀 \(format)），已阻止发送"
        }
        return nil
    }

    /// Mutations are confirmed against a fresh full list, including device-assigned IDs.
    @discardableResult
    public func manageCustomEqualizer(_ action: CustomEQAction, baseline: CustomEqualizer?,
                                      target: CustomEqualizer) -> Bool {
        guard connectionState == .ready, profile == .encoAir5Pro,
              state.operations[.equalizer]?.phase.isPending != true,
              case .ready(let curves) = state.customEqualizerFeature,
              target.payload(for: action) != nil else { return false }
        if action == .create {
            guard baseline == nil, target.id == 0 else { return false }
        } else {
            guard let baseline, curves.contains(baseline), target.id == baseline.id else { return false }
        }
        let id = beginOperation(.equalizer, target: .customEQManagement(action, target, Set(curves.map(\.id))))
        return acceptDispatch(.equalizer, id: id, accepted: commands.setCustomEqualizer(
            target, action: action, dispatched: dispatchHandler(.equalizer, id: id)))
    }

    public func close(intent: ConnectionIntent = .disconnectedByUser) {
        state.customEqualizerFeature = .unknown
        self.intent = intent
        connectionState = .disconnecting
        state.placement = EarbudsPlacementState()
        state.unknownPlacementValues = [:]
        state.batteryObservations = [:]
        onStateChange?()
        initialSyncWorkItem?.cancel()
        initialSyncWorkItem = nil
        cancelOperations()
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
        guard state.operations[.noise]?.phase.isPending != true else { return false }
        let level = profile == .t500Pro && mode == .noiseCancellation ? rememberedLevel : nil
        state.pendingMode = mode
        state.pendingANCLevel = level
        let id = beginOperation(.noise, target: .noise(mode, level))
        return acceptDispatch(.noise, id: id, accepted: commands.setNoiseMode(
            mode, level: level, profile: profile, dispatched: dispatchHandler(.noise, id: id)))
    }

    @discardableResult
    public func set(ancLevel: ANCLevel) -> Bool {
        guard connectionState == .ready, profile.capabilities.contains(.ancLevels),
              state.operations[.noise]?.phase.isPending != true
        else { return false }
        state.pendingMode = .noiseCancellation
        state.pendingANCLevel = ancLevel
        let id = beginOperation(.noise, target: .noise(.noiseCancellation, ancLevel))
        return acceptDispatch(.noise, id: id, accepted: commands.setNoiseMode(
            .noiseCancellation, level: ancLevel, profile: profile,
            dispatched: dispatchHandler(.noise, id: id)))
    }

    @discardableResult
    public func set(equalizer preset: EQPreset) -> Bool {
        guard connectionState == .ready, profile.capabilities.contains(.equalizer),
              state.operations[.equalizer]?.phase.isPending != true
        else { return false }
        state.pendingEqualizer = preset
        let id = beginOperation(.equalizer, target: .equalizer(preset))
        return acceptDispatch(.equalizer, id: id, accepted: commands.setEqualizer(
            preset, profile: profile, dispatched: dispatchHandler(.equalizer, id: id)))
    }

    @discardableResult
    public func set(gameMode enabled: Bool) -> Bool {
        guard connectionState == .ready, profile.capabilities.contains(.gameMode),
              state.operations[.gameMode]?.phase.isPending != true
        else { return false }
        state.pendingGameMode = enabled
        let id = beginOperation(.gameMode, target: .gameMode(enabled))
        return acceptDispatch(.gameMode, id: id, accepted: commands.setGameMode(
            enabled, profile: profile, dispatched: dispatchHandler(.gameMode, id: id)))
    }

    private func beginOperation(_ feature: ControlFeature, target: OperationTarget) -> UInt64 {
        nextOperationID &+= 1
        let id = nextOperationID
        differentObservations.remove(feature)
        state.operations[feature] = FeatureOperation(
            id: id, generation: connectionGeneration, target: target, phase: .queued)
        onStateChange?()
        return id
    }

    private func acceptDispatch(_ feature: ControlFeature, id: UInt64, accepted: Bool) -> Bool {
        if !accepted { finishOperation(feature, id: id, phase: .sendFailed) }
        return accepted
    }

    private func dispatchHandler(_ feature: ControlFeature, id: UInt64) -> (WriteDispatchResult) -> Void {
        { [weak self] result in
            guard let self, self.state.operations[feature]?.id == id,
                  self.state.operations[feature]?.phase == .queued else { return }
            switch result {
            case .sent:
                let sentAt = self.now()
                self.state.operations[feature]?.phase = .sent
                self.state.operations[feature]?.sentAt = sentAt
                self.state.operations[feature]?.deadline = sentAt + 3
                self.schedule(3) { [weak self] in
                    guard let self, self.state.operations[feature]?.id == id,
                          self.state.operations[feature]?.phase == .sent else { return }
                    self.finishOperation(feature, id: id,
                        phase: self.differentObservations.contains(feature) ? .differentState : .timedOut)
                }
                if feature == .equalizer {
                    switch self.state.operations[feature]?.target {
                    case .customEqualizer, .customEQManagement:
                        self.state.equalizerFeature = .unknown
                        self.state.unknownEqualizerMode = nil
                        _ = self.refreshCustomEqualizer(confirmingPendingWrite: true)
                    default:
                        _ = self.queryEqualizer(confirmingPendingWrite: true)
                    }
                }
                if feature == .gameMode { _ = self.queryGameMode(confirmingPendingWrite: true) }
                self.onStateChange?()
            case .failed: self.finishOperation(feature, id: id, phase: .sendFailed)
            case .cancelled: self.finishOperation(feature, id: id, phase: .cancelled)
            }
        }
    }

    private func finishOperation(_ feature: ControlFeature, id: UInt64, phase: OperationPhase) {
        guard state.operations[feature]?.id == id,
              state.operations[feature]?.phase.isPending == true else { return }
        state.operations[feature]?.phase = phase
        switch feature {
        case .noise: state.pendingMode = nil; state.pendingANCLevel = nil
        case .equalizer: state.pendingEqualizer = nil
        case .gameMode: state.pendingGameMode = nil
        }
        onStateChange?()
    }

    private func cancelOperations() {
        for (feature, operation) in state.operations where operation.phase.isPending {
            finishOperation(feature, id: operation.id, phase: .cancelled)
        }
    }

    private func observe(_ feature: ControlFeature, matches: Bool,
                         readbackID: UInt64? = nil, isReadback: Bool = false) {
        guard let operation = state.operations[feature], operation.phase == .sent else { return }
        if isReadback, operation.id != readbackID { return }
        if matches { finishOperation(feature, id: operation.id, phase: .confirmed) }
        else { differentObservations.insert(feature) }
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
            guard connectionState == .openingControlChannel else { return }
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
            guard connectionState == .ready else { return }
            onActivity?()
            receiveBuffer.append(contentsOf: chunk)
            for frame in BudsProtocol.drainFrames(from: &receiveBuffer) {
                commands.receive(frame)
                // Official RequestCommandManager 0x0506: unsolicited full custom-EQ list.
                if profile == .encoAir5Pro, frame.opcode == 0x0605,
                   let curves = CustomEqualizer.decodeList([0] + frame.payload) {
                    state.customEqualizerFeature = .ready(curves)
                }
                apply(BudsProtocol.interpret(frame, profile: profile))
            }

        case .closed:
            state.customEqualizerFeature = .unknown
            connectionState = .idle
            state.placement = EarbudsPlacementState()
            state.unknownPlacementValues = [:]
            state.batteryObservations = [:]
            cancelOperations()
            initialSyncWorkItem?.cancel()
            initialSyncWorkItem = nil
            commands.cancelAll()
            receiveBuffer.removeAll()
            connectionState = .idle
            onStateChange?()

        case .failed(let error):
            state.customEqualizerFeature = .unknown
            connectionState = .failed(.transport(error))
            state.placement = EarbudsPlacementState()
            state.unknownPlacementValues = [:]
            state.batteryObservations = [:]
            cancelOperations()
            initialSyncWorkItem?.cancel()
            initialSyncWorkItem = nil
            commands.cancelAll()
            transport.close()
            receiveBuffer.removeAll()
            connectionState = .failed(.transport(error))
            onStateChange?()
        }
    }

    private func apply(
        _ updates: [BudsProtocol.Update],
        readbackID: UInt64? = nil,
        isReadback: Bool = false
    ) {
        guard !updates.isEmpty else { return }
        var receivedBattery = false
        for update in updates {
            switch update {
            case .noiseMode(let mode):
                state.mode = mode
            case .ancLevel(let level):
                state.ancLevel = level
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
                state.batteryObservations[slot] = BatterySlotObservation(
                    reading: reading, generation: connectionGeneration, observedAt: now())
            case .placement(let slot, let placement):
                state.unknownPlacementValues.removeValue(forKey: slot)
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
            case .unknownPlacement(let slot, let value):
                state.placement[slot] = nil
                state.unknownPlacementValues[slot] = value
            case .unknownEqualizer(let value):
                state.unknownEqualizerMode = value
                state.equalizerFeature = .unknown
                if case .ready(let curves) = state.customEqualizerFeature {
                    state.customEqualizerFeature = .ready(curves.map { $0.selecting($0.id == value) })
                }
                observe(.equalizer, matches: false,
                        readbackID: readbackID, isReadback: isReadback)
            case .deviceInformation(let information):
                state.deviceInformationFeature = .ready(information)
            case .equalizer(let preset):
                state.unknownEqualizerMode = nil
                state.equalizerFeature = .ready(preset)
                if case .ready(let curves) = state.customEqualizerFeature {
                    state.customEqualizerFeature = .ready(curves.map { $0.selecting(false) })
                }
                observe(.equalizer, matches: state.pendingEqualizer == preset,
                        readbackID: readbackID, isReadback: isReadback)
            case .gameMode(let enabled):
                state.gameModeFeature = .ready(enabled)
                observe(.gameMode, matches: state.pendingGameMode == enabled,
                        readbackID: readbackID, isReadback: isReadback)
            }
        }
        if receivedBattery {
            state.batteryFeature = .ready(state.battery)
        }
        let noiseModes = updates.compactMap { update -> NoiseMode? in
            if case .noiseMode(let mode) = update { return mode }; return nil
        }
        let levels = updates.compactMap { update -> ANCLevel? in
            if case .ancLevel(let level) = update { return level }; return nil
        }
        if !noiseModes.isEmpty {
            observe(.noise, matches: noiseModes.contains(where: { $0 == state.pendingMode })
                && (state.pendingANCLevel == nil || levels.contains(where: { $0 == state.pendingANCLevel })))
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
        schedule(0.2) { work.perform() }
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
        state.soundRefresh[.equalizer] = .loading
        onStateChange?()
        let readbackID = state.operations[.equalizer]?.phase == .sent
            ? state.operations[.equalizer]?.id : nil
        switch state.equalizerFeature {
        case .ready:
            break
        default:
            state.equalizerFeature = .loading
            onStateChange?()
        }
        guard commands.enqueueEqualizerQuery(
            profile: profile,
            verification: confirmingPendingWrite,
            completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                let updates = BudsProtocol.interpretEqualizerResponse(
                    frame, profile: self.profile)
                if updates.isEmpty {
                    self.state.soundRefresh[.equalizer] = .failed("均衡器响应格式异常")
                    if case .ready = self.state.equalizerFeature {
                        self.onStateChange?()
                        return
                    }
                    self.state.equalizerFeature = .failed("均衡器响应格式异常")
                    self.onStateChange?()
                } else {
                    self.state.soundRefresh[.equalizer] = .idle
                    self.apply(updates, readbackID: readbackID, isReadback: true)
                }
            case .failure(.cancelled):
                self.state.soundRefresh[.equalizer] = .idle
                return
            case .failure:
                self.state.soundRefresh[.equalizer] = .failed("读取均衡器失败")
                if case .ready = self.state.equalizerFeature {
                    self.onStateChange?()
                    return
                }
                self.state.equalizerFeature = .failed("读取均衡器失败")
                self.onStateChange?()
            }
        }) else {
            state.soundRefresh[.equalizer] = .idle
            state.equalizerFeature = .unsupported
            state.pendingEqualizer = nil
            onStateChange?()
            return false
        }
        return true
    }

    @discardableResult
    private func queryGameMode(confirmingPendingWrite: Bool = false) -> Bool {
        state.soundRefresh[.gameMode] = .loading
        onStateChange?()
        let readbackID = state.operations[.gameMode]?.phase == .sent
            ? state.operations[.gameMode]?.id : nil
        switch state.gameModeFeature {
        case .ready:
            break
        default:
            state.gameModeFeature = .loading
            onStateChange?()
        }
        guard commands.enqueueGameModeQuery(
            profile: profile,
            verification: confirmingPendingWrite,
            completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                let updates = BudsProtocol.interpretGameModeResponse(
                    frame, profile: self.profile)
                if updates.isEmpty {
                    self.state.soundRefresh[.gameMode] = .failed("游戏模式响应格式异常")
                    if case .ready = self.state.gameModeFeature {
                        self.onStateChange?()
                        return
                    }
                    self.state.gameModeFeature = .failed("游戏模式响应格式异常")
                    self.onStateChange?()
                } else {
                    self.state.soundRefresh[.gameMode] = .idle
                    self.apply(updates, readbackID: readbackID, isReadback: true)
                }
            case .failure(.cancelled):
                self.state.soundRefresh[.gameMode] = .idle
                return
            case .failure:
                self.state.soundRefresh[.gameMode] = .failed("读取游戏模式失败")
                if case .ready = self.state.gameModeFeature {
                    self.onStateChange?()
                    return
                }
                self.state.gameModeFeature = .failed("读取游戏模式失败")
                self.onStateChange?()
            }
        }) else {
            state.soundRefresh[.gameMode] = .idle
            state.gameModeFeature = .unsupported
            state.pendingGameMode = nil
            onStateChange?()
            return false
        }
        return true
    }
}
