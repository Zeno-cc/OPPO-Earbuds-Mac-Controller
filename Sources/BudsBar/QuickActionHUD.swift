import AppKit
import BudsCore
import SwiftUI

/// What the user should be told about a quick control triggered from outside the panel.
enum QuickActionFeedback: Equatable {
    /// The command was handed to the session; the buds have not answered yet.
    case submitted
    /// The buds confirmed the requested mode.
    case confirmed(NoiseMode, ANCLevel?)
    /// The command could not be confirmed, with the reason to show.
    case failed(String)
}

/// How much of a quick action's lifecycle should be narrated.
///
/// A menu selection is deliberate and the menu itself is the acknowledgement, so only its
/// failures surface. Option-click and the global hotkey leave no other trace, so they report
/// both the attempt and the outcome.
enum QuickActionFeedbackStyle {
    case full
    case failuresOnly
}

/// Non-activating HUD for quick noise-control feedback.
///
/// Deliberately separate from `ConnectionHUDCoordinator`: a quick action must never touch the
/// connection state machine, it only borrows the same screen slot so the two never occupy it
/// at once. `AppDelegate` wires that arbitration.
final class QuickActionHUDController {

    /// Fires when the HUD takes or releases the shared HUD slot.
    var onVisibilityChange: ((Bool) -> Void)?

    private static let holdDuration: TimeInterval = 1.6
    private static let size = NSSize(width: 268, height: 52)

    private let panel: NSPanel
    private var hideWorkItem: DispatchWorkItem?
    private var isShowing = false
    /// Guards the fade-out completion, so a feedback that arrives mid-fade is not
    /// immediately ordered out by the previous animation.
    private var presentationGeneration = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: QuickActionHUDView(feedback: .submitted))
    }

    func show(_ feedback: QuickActionFeedback) {
        hideWorkItem?.cancel()
        presentationGeneration += 1
        panel.contentView = NSHostingView(rootView: QuickActionHUDView(feedback: feedback))
        positionOnPointerScreen()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        setShowing(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.16
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: work)
    }

    func hide() {
        guard panel.isVisible else { return }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        let generation = presentationGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.panel.orderOut(nil)
            self.setShowing(false)
        }
    }

    private func setShowing(_ value: Bool) {
        guard isShowing != value else { return }
        isShowing = value
        onVisibilityChange?(value)
    }

    /// Same slot as the connection HUD's compact card: top-right of the pointer's screen.
    private func positionOnPointerScreen() {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.maxX - Self.size.width - 24,
            y: visibleFrame.maxY - Self.size.height - 22))
    }
}

private struct QuickActionHUDView: View {
    let feedback: QuickActionFeedback

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var text: String {
        switch feedback {
        case .submitted:
            return "正在切换降噪模式…"
        case .confirmed(let mode, let level):
            guard mode == .noiseCancellation, let level else { return "已切换到 \(mode.label)" }
            return "已切换到 \(mode.label) · \(level.label)"
        case .failed(let message):
            return message
        }
    }

    private var symbol: String {
        switch feedback {
        case .submitted: return "hourglass"
        case .confirmed(let mode, _): return mode.symbol
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch feedback {
        case .submitted: return .secondary
        case .confirmed: return .accentColor
        case .failed: return .orange
        }
    }
}
