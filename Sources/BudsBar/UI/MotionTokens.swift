import SwiftUI

enum MotionTokens {
    static let instant: TimeInterval = 0
    static let fast: TimeInterval = 0.12
    static let standard: TimeInterval = 0.18
    static let slow: TimeInterval = 0.28
    static let battery: TimeInterval = 0.22

    static func state(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: fast) : .easeOut(duration: standard)
    }

    static func hudEntry(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? fast : slow)
    }
}

enum HUDMotionTokens {
    static let compactEnter: TimeInterval = 0.22
    static let compactHold: TimeInterval = 0.14
    static let expand: TimeInterval = 0.42
    static let batteryRevealDelay: TimeInterval = 0.18
    static let modeRevealDelay: TimeInterval = 0.10
    static let expandSettle: TimeInterval = 0.14
    static let expandedHold: TimeInterval = 2.65
    static let secondaryContent: TimeInterval = 0.26
    static let secondaryFade: TimeInterval = 0.18
    static let collapse: TimeInterval = 0.32
    static let compactExitHold: TimeInterval = 0.14
    static let dismiss: TimeInterval = 0.20
    static let reducedTransition: TimeInterval = 0.12
    static let hoverExitHold: TimeInterval = 1.60
    static let springResponse: TimeInterval = 0.48
    static let springDamping = 0.80

    static let totalPresentationDuration =
        compactEnter + compactHold + expand + expandedHold + secondaryFade
        + collapse + compactExitHold + dismiss
}
