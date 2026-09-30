import AppKit

/// A drag-local policy: suppress duplicates and fast ticks, never queue feedback.
struct EQSliderHapticFeedback {
    private var previousGain: Int8?
    private var lastFeedbackTime: TimeInterval?
    static let minimumInterval: TimeInterval = 0.05

    mutating func begin(at gain: Int8) {
        previousGain = gain
        lastFeedbackTime = nil
    }

    mutating func end() {
        previousGain = nil
        lastFeedbackTime = nil
    }

    mutating func feedback(for gain: Int8, at time: TimeInterval) -> NSHapticFeedbackManager.FeedbackPattern? {
        guard let previousGain, previousGain != gain else { return nil }
        self.previousGain = gain
        if let lastFeedbackTime, time - lastFeedbackTime < Self.minimumInterval { return nil }
        lastFeedbackTime = time
        // Alignment for each detent; generic distinguishes the neutral value.
        // AppKit owns intensity, hardware support and user preferences.
        return gain == 0 ? .generic : .alignment
    }
}

/// Retain NSSlider's own tracking, keyboard and accessibility implementation.
final class EQHapticSlider: NSSlider {
    private var isPointerTracking = false
    private var feedback = EQSliderHapticFeedback()

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { super.mouseDown(with: event); return }
        isPointerTracking = true
        feedback.begin(at: Int8(doubleValue.rounded()))
        defer {
            isPointerTracking = false
            feedback.end()
        }
        super.mouseDown(with: event)
    }

    func didChangeGain(_ gain: Int8) {
        // Keyboard, VoiceOver, clicks and programmatic curve loads are silent.
        guard isPointerTracking else { return }
        if NSApp.currentEvent?.type == .leftMouseDown {
            // A click on the track may jump to a new value before dragging starts.
            feedback.begin(at: gain)
            return
        }
        guard NSApp.currentEvent?.type == .leftMouseDragged,
              let pattern = feedback.feedback(for: gain, at: ProcessInfo.processInfo.systemUptime) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
