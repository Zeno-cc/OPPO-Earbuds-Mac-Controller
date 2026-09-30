import Foundation

struct ConnectionExperienceObservation: Equatable {
    let isConnected: Bool
    let suppressUnexpectedDisconnect: Bool
    let deviceIdentity: String?

    init(isConnected: Bool, suppressUnexpectedDisconnect: Bool = false, deviceIdentity: String? = nil) {
        self.isConnected = isConnected
        self.suppressUnexpectedDisconnect = suppressUnexpectedDisconnect
        self.deviceIdentity = deviceIdentity
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
    private var deviceIdentity: String?
    private var pendingUnexpectedDisconnect = false
    private var reconnectIsExpected = false
    private var lastPresentation: (event: ConnectionHUDEvent, date: Date)?

    mutating func observe(
        _ observation: ConnectionExperienceObservation,
        at date: Date = Date()
    ) -> [ConnectionExperienceEffect] {
        if lastConnected != nil, deviceIdentity != observation.deviceIdentity {
            lastPresentation = nil
            return rebaseline(observation)
        }
        deviceIdentity = observation.deviceIdentity
        guard let previous = lastConnected else {
            lastConnected = observation.isConnected
            return [.establishBaseline]
        }
        if !observation.isConnected, observation.suppressUnexpectedDisconnect {
            let shouldCancel = pendingUnexpectedDisconnect
            pendingUnexpectedDisconnect = false
            reconnectIsExpected = false
            lastPresentation = nil
            lastConnected = false
            return shouldCancel ? [.cancelUnexpectedDisconnect] : []
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
        if deviceIdentity != observation.deviceIdentity {
            lastPresentation = nil
        }
        deviceIdentity = observation.deviceIdentity
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
