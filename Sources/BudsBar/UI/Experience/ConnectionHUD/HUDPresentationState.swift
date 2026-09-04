import AppKit

enum HUDExpansionPhase: Equatable {
    case container
    case battery
    case complete
}

enum HUDCollapsePhase: Equatable {
    case content
    case container
}

enum HUDPresentationState: Equatable {
    case hidden
    case compact
    case expanding(HUDExpansionPhase)
    case expanded
    case collapsing(HUDCollapsePhase)
    case dismissing

    var usesExpandedGeometry: Bool {
        switch self {
        case .expanding, .expanded, .collapsing(.content): true
        case .hidden, .compact, .collapsing(.container), .dismissing: false
        }
    }

    var keepsSecondaryLayout: Bool {
        switch self {
        case .expanding, .expanded, .collapsing(.content): true
        case .hidden, .compact, .collapsing(.container), .dismissing: false
        }
    }

    var showsBattery: Bool {
        switch self {
        case .expanding(.battery), .expanding(.complete), .expanded: true
        case .hidden, .compact, .expanding(.container), .collapsing, .dismissing: false
        }
    }

    var showsMode: Bool {
        switch self {
        case .expanding(.complete), .expanded: true
        case .hidden, .compact, .expanding, .collapsing, .dismissing: false
        }
    }
}

struct HUDPresentationLifecycle {
    private(set) var state: HUDPresentationState = .hidden

    @discardableResult
    mutating func start() -> HUDPresentationState {
        state = .compact
        return state
    }

    @discardableResult
    mutating func restartExpansion() -> HUDPresentationState {
        state = .expanding(.container)
        return state
    }

    @discardableResult
    mutating func advance() -> HUDPresentationState {
        switch state {
        case .hidden:
            state = .compact
        case .compact:
            state = .expanding(.container)
        case .expanding(.container):
            state = .expanding(.battery)
        case .expanding(.battery):
            state = .expanding(.complete)
        case .expanding(.complete):
            state = .expanded
        case .expanded:
            state = .collapsing(.content)
        case .collapsing(.content):
            state = .collapsing(.container)
        case .collapsing(.container):
            state = .dismissing
        case .dismissing:
            state = .hidden
        }
        return state
    }
}

enum HUDPanelLayout {
    static let compactSize = NSSize(width: 268, height: 64)

    static func expandedSize(
        event: ConnectionHUDEvent,
        hasBattery: Bool,
        hasMode: Bool
    ) -> NSSize {
        if event == .unexpectedDisconnected {
            return NSSize(width: 330, height: 92)
        }
        if hasBattery && hasMode {
            return NSSize(width: 350, height: 120)
        }
        if hasBattery || hasMode {
            return NSSize(width: 350, height: 108)
        }
        return NSSize(width: 330, height: 92)
    }
}
