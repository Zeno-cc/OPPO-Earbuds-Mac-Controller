import AppKit
import SwiftUI
import Testing
@testable import BudsBar

struct EQSliderHapticTests {
    @Test func feedbackRequiresActiveDragAndChangedDetent() {
        var feedback = EQSliderHapticFeedback()
        #expect(feedback.feedback(for: 1, at: 0) == nil)
        feedback.begin(at: 0)
        #expect(feedback.feedback(for: 0, at: 0) == nil)
        #expect(feedback.feedback(for: 1, at: 0.1) == .alignment)
        #expect(feedback.feedback(for: 1, at: 0.2) == nil)
        #expect(feedback.feedback(for: 2, at: 0.3) == .alignment)
        feedback.end()
        #expect(feedback.feedback(for: 3, at: 0.4) == nil)
    }

    @Test func zeroUsesDistinctPatternInEitherDirection() {
        for initial: Int8 in [-1, 1] {
            var feedback = EQSliderHapticFeedback()
            feedback.begin(at: initial)
            #expect(feedback.feedback(for: 0, at: 1) == .generic)
            #expect(feedback.feedback(for: 0, at: 2) == nil)
            #expect(feedback.feedback(for: initial, at: 3) == .alignment)
        }
    }

    @Test func fastMovementDropsTicksWithoutDelayedReplay() {
        var feedback = EQSliderHapticFeedback()
        feedback.begin(at: -6)
        #expect(feedback.feedback(for: -5, at: 1) == .alignment)
        #expect(feedback.feedback(for: -4, at: 1.01) == nil)
        #expect(feedback.feedback(for: -3, at: 1.02) == nil)
        #expect(feedback.feedback(for: -3, at: 2) == nil)
        #expect(feedback.feedback(for: -2, at: 2.1) == .alignment)
    }

    @Test func skippedIntermediateValuesProduceOnlyOneTick() {
        var feedback = EQSliderHapticFeedback()
        feedback.begin(at: -6)
        #expect(feedback.feedback(for: 6, at: 1) == .alignment)
        #expect(feedback.feedback(for: 6, at: 2) == nil)
        #expect(feedback.feedback(for: 0, at: 3) == .generic)
    }

    @Test func nextDragResetsRateLimitAndStartingValue() {
        var feedback = EQSliderHapticFeedback()
        feedback.begin(at: 1)
        #expect(feedback.feedback(for: 2, at: 1) == .alignment)
        feedback.end()
        feedback.begin(at: -1)
        #expect(feedback.feedback(for: -1, at: 1.01) == nil)
        #expect(feedback.feedback(for: 0, at: 1.02) == .generic)
    }

    @MainActor @Test func coordinatorRetainsImmediateBindingAndNativeSlider() {
        _ = NSApplication.shared
        var gain: Int8 = 0
        let binding = Binding<Int8>(get: { gain }, set: { gain = $0 })
        let coordinator = EQBandSlider.Coordinator(value: binding)
        let slider = EQBandSlider.makeSlider()
        #expect(slider is EQHapticSlider)
        slider.doubleValue = 4
        coordinator.changed(slider)
        #expect(gain == 4)
        slider.doubleValue = -6
        coordinator.changed(slider)
        #expect(gain == -6)
        #expect(slider.isVertical && slider.allowsTickMarkValuesOnly && slider.isContinuous)
        #expect(slider.numberOfTickMarks == 13)
    }
}
