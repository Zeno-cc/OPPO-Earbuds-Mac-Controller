import Foundation

struct ConnectionExperienceObservation: Equatable {
    let isConnected: Bool
    let suppressUnexpectedDisconnect: Bool

    init(isConnected: Bool, suppressUnexpectedDisconnect: Bool = false) {
        self.isConnected = isConnected
        self.suppressUnexpectedDisconnect = suppressUnexpectedDisconnect
    }
}

enum ConnectionHUDEvent: Equatable {
    case connected
    case reconnected
    case unexpectedDisconnected
}

enum ConnectionExperienceEffect: Equatable {
    case establishBaseline
    case scheduleUnexpectedDisconnect(after: TimeInterval)
    case cancelUnexpectedDisconnect
    case present(ConnectionHUDEvent)
}

struct ConnectionExperience {
    static let disconnectDebounce: TimeInterval = 0.65
    static let duplicateWindow: TimeInterval = 5

    private var lastConnected: Bool?
    private var pendingUnexpectedDisconnect = false
    private var reconnectIsExpected = false
    private var lastPresentation: (event: ConnectionHUDEvent, date: Date)?

    mutating func observe(
        _ observation: ConnectionExperienceObservation,
        at date: Date = Date()
    ) -> [ConnectionExperienceEffect] {
        guard let previous = lastConnected else {
            lastConnected = observation.isConnected
            return [.establishBaseline]
        }
        guard previous != observation.isConnected else { return [] }
        lastConnected = observation.isConnected

        if observation.isConnected {
            if pendingUnexpectedDisconnect {
                pendingUnexpectedDisconnect = false
                reconnectIsExpected = false
                return [.cancelUnexpectedDisconnect] + presentation(.reconnected, at: date)
            }
            let event: ConnectionHUDEvent = reconnectIsExpected ? .reconnected : .connected
            reconnectIsExpected = false
            return presentation(event, at: date)
        }

        if observation.suppressUnexpectedDisconnect {
            pendingUnexpectedDisconnect = false
            reconnectIsExpected = false
            // A deliberate disconnect is the opposite lifecycle transition. It is not
            // presented, but it must allow a subsequent user-requested connection to be
            // shown even when the previous connected HUD is still inside the dedupe window.
            lastPresentation = nil
            return []
        }

        pendingUnexpectedDisconnect = true
        reconnectIsExpected = true
        return [.scheduleUnexpectedDisconnect(after: Self.disconnectDebounce)]
    }

    mutating func confirmUnexpectedDisconnect(
        at date: Date = Date()
    ) -> ConnectionExperienceEffect? {
        guard pendingUnexpectedDisconnect, lastConnected == false else { return nil }
        pendingUnexpectedDisconnect = false
        return presentation(.unexpectedDisconnected, at: date).first
    }

    @discardableResult
    mutating func rebaseline(
        _ observation: ConnectionExperienceObservation
    ) -> [ConnectionExperienceEffect] {
        let shouldCancel = pendingUnexpectedDisconnect
        pendingUnexpectedDisconnect = false
        reconnectIsExpected = false
        lastConnected = observation.isConnected
        return shouldCancel ? [.cancelUnexpectedDisconnect] : []
    }

    private mutating func presentation(
        _ event: ConnectionHUDEvent,
        at date: Date
    ) -> [ConnectionExperienceEffect] {
        if let lastPresentation,
           lastPresentation.event == event,
           date.timeIntervalSince(lastPresentation.date) < Self.duplicateWindow {
            return []
        }
        lastPresentation = (event, date)
        return [.present(event)]
    }
}
