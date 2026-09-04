import Foundation

final class ConnectionHUDCoordinator {
    private var experience = ConnectionExperience()
    private let panelController: ConnectionHUDPanelController
    private let snapshot: (ConnectionHUDEvent) -> HUDSnapshot
    private let isEnabled: (ConnectionHUDEvent) -> Bool
    private var disconnectWorkItem: DispatchWorkItem?
    private var readinessWorkItem: DispatchWorkItem?
    private var waitingEvent: ConnectionHUDEvent?

    init(
        panelController: ConnectionHUDPanelController = ConnectionHUDPanelController(),
        snapshot: @escaping (ConnectionHUDEvent) -> HUDSnapshot,
        isEnabled: @escaping (ConnectionHUDEvent) -> Bool
    ) {
        self.panelController = panelController
        self.snapshot = snapshot
        self.isEnabled = isEnabled
    }

    func observe(_ observation: ConnectionExperienceObservation, at date: Date = Date()) {
        if let waitingEvent {
            let current = snapshot(waitingEvent)
            if current.hasPresentationDetails {
                show(waitingEvent, snapshot: current)
            }
        }
        if let visibleEvent = panelController.visibleEvent {
            panelController.update(snapshot: snapshot(visibleEvent))
        }

        for effect in experience.observe(observation, at: date) {
            handle(effect)
        }
    }

    func stabilize(with observation: ConnectionExperienceObservation) {
        for effect in experience.rebaseline(observation) {
            handle(effect)
        }
        readinessWorkItem?.cancel()
        readinessWorkItem = nil
        waitingEvent = nil
        panelController.dismiss()
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
        readinessWorkItem?.cancel()
        readinessWorkItem = nil
        waitingEvent = nil
        guard isEnabled(event) else { return }

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
        readinessWorkItem?.cancel()
        readinessWorkItem = nil
        waitingEvent = nil
        panelController.show(event: event, snapshot: snapshot)
    }
}
