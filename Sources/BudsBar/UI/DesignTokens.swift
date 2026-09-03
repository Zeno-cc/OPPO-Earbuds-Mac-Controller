// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V5
// Hallmark · genre: modern-minimal · structure: fixed status + capped section stack
// Restraint: system typography, semantic colors, one root material, no nested card chrome.
import SwiftUI

enum PanelDesignTokens {
    static let width: CGFloat = 368
    static let maximumHeight: CGFloat = 556

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24

    static let sectionSpacing: CGFloat = 18
    static let sectionRadius: CGFloat = 10
    static let primaryControlHeight: CGFloat = 36
    static let secondaryControlHeight: CGFloat = 30
    static let dividerOpacity = 0.12
    static let stateAnimationDuration = 0.18

    static func stateAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: stateAnimationDuration)
    }
}
