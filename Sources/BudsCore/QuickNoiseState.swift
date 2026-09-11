import Foundation

/// Toggle state for the panel-less quick control.
///
/// The waiting case exists because the protocol has no mode query: the buds report the noise
/// mode when they choose to. A press that lands before the first report has nothing to invert
/// yet, so it arms a one-shot intent instead — armed once, resolved at most once, and dropped
/// after `intentTimeout`. The intent deliberately does not remember a target mode: what to
/// send is decided when the real mode arrives, so an unknown-mode press still toggles.
public struct QuickNoiseState: Equatable {
    public var confirmedMode: NoiseMode?
    public var isWaitingForMode: Bool
    public var pendingGeneration: UInt64?
    public var pendingSince: TimeInterval?
    public var operationPending: Bool

    public init(confirmedMode: NoiseMode? = nil,
                isWaitingForMode: Bool = false, pendingGeneration: UInt64? = nil,
                pendingSince: TimeInterval? = nil, operationPending: Bool = false) {
        self.confirmedMode = confirmedMode
        self.isWaitingForMode = isWaitingForMode
        self.pendingGeneration = pendingGeneration
        self.pendingSince = pendingSince
        self.operationPending = operationPending
    }
}

public enum QuickNoiseDecision: Equatable {
    case send(NoiseMode)
    case waitForMode
    case ignored
}

public enum QuickNoiseReducer {
    public static let intentTimeout: TimeInterval = 2

    /// ANC goes to transparency; transparency and off both go back to noise cancellation.
    public static func target(for mode: NoiseMode) -> NoiseMode {
        mode == .noiseCancellation ? .transparency : .noiseCancellation
    }

    public static func toggle(_ state: inout QuickNoiseState, generation: UInt64,
                              now: TimeInterval) -> QuickNoiseDecision {
        guard !state.operationPending else { return .ignored }
        if let mode = state.confirmedMode { return .send(target(for: mode)) }
        // A live intent already covers this press: it neither extends the window nor sends a
        // second command. An expired one is dropped and re-armed by the lines below.
        if hasLiveIntent(state, generation: generation, now: now) { return .waitForMode }
        clearIntent(&state)
        state.isWaitingForMode = true
        state.pendingGeneration = generation
        state.pendingSince = now
        return .waitForMode
    }

    /// Resolves the armed intent against the mode the buds actually reported.
    public static func modeArrived(_ state: inout QuickNoiseState, mode: NoiseMode,
                                   generation: UInt64, now: TimeInterval) -> QuickNoiseDecision {
        state.confirmedMode = mode
        guard hasLiveIntent(state, generation: generation, now: now) else {
            clearIntent(&state)
            return .ignored
        }
        clearIntent(&state)
        return .send(target(for: mode))
    }

    public static func cancel(_ state: inout QuickNoiseState) { clearIntent(&state) }

    public static func hasLiveIntent(_ state: QuickNoiseState, generation: UInt64,
                                     now: TimeInterval) -> Bool {
        guard state.isWaitingForMode, state.pendingGeneration == generation,
              let since = state.pendingSince else { return false }
        return now - since <= intentTimeout
    }

    private static func clearIntent(_ state: inout QuickNoiseState) {
        state.isWaitingForMode = false
        state.pendingGeneration = nil
        state.pendingSince = nil
    }
}
