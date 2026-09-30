import Foundation

final class ConnectionHUDCoordinator {
    private var experience = ConnectionExperience()
    private let panelController: ConnectionHUDPanelController
    private let snapshot: (ConnectionHUDEvent) -> HUDSnapshot
    private let isEnabled: (ConnectionHUDEvent) -> Bool
    /// True while another, user-triggered HUD owns the shared screen slot.
    private let isSlotBusy: () -> Bool
    private var disconnectWorkItem: DispatchWorkItem?
    private var readinessWorkItem: DispatchWorkItem?
    private var waitingEvent: ConnectionHUDEvent?
    private var latestObservation: ConnectionExperienceObservation?

    init(
        panelController: ConnectionHUDPanelController = ConnectionHUDPanelController(),
        snapshot: @escaping (ConnectionHUDEvent) -> HUDSnapshot,
        isEnabled: @escaping (ConnectionHUDEvent) -> Bool,
        isSlotBusy: @escaping () -> Bool
    ) {
        self.panelController = panelController
        self.snapshot = snapshot
        self.isEnabled = isEnabled
        self.isSlotBusy = isSlotBusy
    }

    func observe(_ observation: ConnectionExperienceObservation, at date: Date = Date()) {
        let identityChanged = latestObservation.map {
            $0.deviceIdentity != observation.deviceIdentity
        } ?? false
        latestObservation = observation
        if identityChanged {
            clearWaitingPresentation()
            panelController.dismissImmediately()
        }
        if let waitingEvent, !isApplicable(waitingEvent) {
            clearWaitingPresentation()
        }
        if let visibleEvent = panelController.visibleEvent,
           !isApplicable(visibleEvent) || isSlotBusy() {
            panelController.dismissImmediately()
        }

        for effect in experience.observe(observation, at: date) {
            handle(effect)
        }
        if let waitingEvent, !isSlotBusy() {
            let current = snapshot(waitingEvent)
            if current.hasPresentationDetails {
                show(waitingEvent, snapshot: current)
            }
        }
        if let visibleEvent = panelController.visibleEvent {
            panelController.update(snapshot: snapshot(visibleEvent))
        }
    }

    func stabilize(with observation: ConnectionExperienceObservation) {
        latestObservation = observation
        for effect in experience.rebaseline(observation) {
            handle(effect)
        }
        clearWaitingPresentation()
        panelController.dismissImmediately()
    }

    /// Called when another HUD takes the shared slot.
    func yieldSlot() {
        readinessWorkItem?.cancel()
        readinessWorkItem = nil
        panelController.dismissImmediately()
    }

    /// Called when the shared slot is free again, so a deferred event can land.
    func retryDeferredPresentation() {
        guard let waitingEvent else { return }
        beginPresentation(waitingEvent)
    }

    private func handle(_ effect: ConnectionExperienceEffect) {
        switch effect {
        case .establishBaseline:
            break
        case .cancelUnexpectedDisconnect:
            disconnectWorkItem?.cancel()
            disconnectWorkItem = nil
        case .scheduleUnexpectedDisconnect(let delay):
            disconnectWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.disconnectWorkItem = nil
                if let effect = self.experience.confirmUnexpectedDisconnect() {
                    self.handle(effect)
                }
            }
            disconnectWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        case .present(let event):
            beginPresentation(event)
        }
    }

    private func beginPresentation(_ event: ConnectionHUDEvent) {
        clearWaitingPresentation()
        guard isApplicable(event) else { return }
        // The quick-action HUD wins the slot; keep the event queued instead of dropping it.
        guard !isSlotBusy() else {
            waitingEvent = event
            return
        }

        let current = snapshot(event)
        guard event != .unexpectedDisconnected, !current.hasPresentationDetails else {
            show(event, snapshot: current)
            return
        }

        waitingEvent = event
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.waitingEvent == event else { return }
            self.show(event, snapshot: self.snapshot(event))
        }
        readinessWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func show(_ event: ConnectionHUDEvent, snapshot: HUDSnapshot) {
        clearWaitingPresentation()
        guard isApplicable(event) else { return }
        guard !isSlotBusy() else {
            waitingEvent = event
            return
        }
        panelController.show(event: event, snapshot: snapshot)
    }

    private func isApplicable(_ event: ConnectionHUDEvent) -> Bool {
        guard let observation = latestObservation, isEnabled(event) else { return false }
        switch event {
        case .connected, .reconnected:
            return observation.isConnected
        case .unexpectedDisconnected:
            return !observation.isConnected && !observation.suppressUnexpectedDisconnect
        }
    }

    private func clearWaitingPresentation() {
        readinessWorkItem?.cancel()
        readinessWorkItem = nil
        waitingEvent = nil
    }
}
