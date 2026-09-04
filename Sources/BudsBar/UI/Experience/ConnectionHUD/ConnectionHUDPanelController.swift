import AppKit
import SwiftUI

private final class ConnectionHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ConnectionHUDViewModel: ObservableObject {
    @Published var event: ConnectionHUDEvent = .connected
    @Published var snapshot: HUDSnapshot?
    @Published var presentationState: HUDPresentationState = .hidden
    @Published var connectedPulseTrigger = 0
    var onHoverChange: ((Bool) -> Void)?
}

final class ConnectionHUDPanelController {
    private let panel: NSPanel
    private let model = ConnectionHUDViewModel()
    private var lifecycle = HUDPresentationLifecycle()
    private var transitionWorkItem: DispatchWorkItem?
    private var presentationGeneration = 0
    private var presentationVisibleFrame: NSRect?
    private var isHovering = false
    private(set) var visibleEvent: ConnectionHUDEvent?

    init() {
        panel = ConnectionHUDPanel(
            contentRect: NSRect(origin: .zero, size: HUDPanelLayout.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = NSHostingController(rootView: ConnectionHUDView(model: model))
        model.onHoverChange = { [weak self] hovering in
            self?.hoverChanged(hovering)
        }
    }

    func show(event: ConnectionHUDEvent, snapshot: HUDSnapshot) {
        let wasVisible = panel.isVisible
        presentationGeneration += 1
        cancelTransition()
        model.event = event
        model.snapshot = snapshot
        visibleEvent = event
        isHovering = false

        if wasVisible {
            continueWithNewEvent()
        } else {
            beginPresentation()
        }
    }

    func update(snapshot: HUDSnapshot) {
        guard visibleEvent != nil else { return }
        model.snapshot = snapshot
        guard model.presentationState.usesExpandedGeometry else { return }
        resizePanel(for: model.presentationState, duration: MotionTokens.standard)
    }

    func dismiss() {
        guard panel.isVisible else {
            resetHiddenState()
            return
        }
        presentationGeneration += 1
        cancelTransition()
        beginDismissal(duration: HUDMotionTokens.dismiss)
    }

    private func beginPresentation() {
        lifecycle = HUDPresentationLifecycle()
        model.presentationState = lifecycle.start()
        if model.event != .unexpectedDisconnected {
            model.connectedPulseTrigger += 1
        }
        presentationVisibleFrame = pointerScreenVisibleFrame()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        let entryOffset: CGFloat = reduceMotion ? 0 : 10
        panel.setFrame(
            targetFrame(size: HUDPanelLayout.compactSize, yOffset: entryOffset),
            display: false)
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion
                ? HUDMotionTokens.reducedTransition
                : HUDMotionTokens.compactEnter
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(
                    targetFrame(size: HUDPanelLayout.compactSize),
                    display: true)
            }
        }

        if reduceMotion {
            schedule(after: HUDMotionTokens.reducedTransition) { [weak self] in
                self?.beginReducedExpandedState()
            }
        } else {
            scheduleAdvance(after: HUDMotionTokens.compactEnter + HUDMotionTokens.compactHold)
        }
    }

    private func continueWithNewEvent() {
        panel.alphaValue = 1
        lifecycle = HUDPresentationLifecycle()
        let state = lifecycle.restartExpansion()
        model.presentationState = state

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            beginReducedExpandedState()
        } else {
            resizePanel(for: state, duration: HUDMotionTokens.expand)
            scheduleAdvance(after: HUDMotionTokens.batteryRevealDelay)
        }
    }

    private func scheduleAdvance(after delay: TimeInterval) {
        schedule(after: delay) { [weak self] in
            guard let self else { return }
            let next = self.lifecycle.advance()
            self.model.presentationState = next
            self.applyTransition(to: next)
        }
    }

    private func applyTransition(to next: HUDPresentationState) {
        switch next {
        case .expanding(.container):
            resizePanel(for: next, duration: HUDMotionTokens.expand)
            scheduleAdvance(after: HUDMotionTokens.batteryRevealDelay)
        case .expanding(.battery):
            scheduleAdvance(after: HUDMotionTokens.modeRevealDelay)
        case .expanding(.complete):
            scheduleAdvance(after: HUDMotionTokens.expandSettle)
        case .expanded:
            scheduleExpandedHold()
        case .collapsing(.content):
            scheduleAdvance(after: HUDMotionTokens.secondaryFade)
        case .collapsing(.container):
            resizePanel(for: next, duration: HUDMotionTokens.collapse)
            scheduleAdvance(after: HUDMotionTokens.collapse + HUDMotionTokens.compactExitHold)
        case .dismissing:
            beginDismissal(duration: HUDMotionTokens.dismiss, advancesLifecycle: true)
        case .hidden:
            finishPresentation()
        case .compact:
            scheduleAdvance(after: HUDMotionTokens.compactEnter + HUDMotionTokens.compactHold)
        }
    }

    private func scheduleExpandedHold(after delay: TimeInterval = HUDMotionTokens.expandedHold) {
        guard !isHovering else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            schedule(after: delay) { [weak self] in
                self?.beginDismissal(duration: HUDMotionTokens.reducedTransition)
            }
        } else {
            scheduleAdvance(after: delay)
        }
    }

    private func beginReducedExpandedState() {
        lifecycle = HUDPresentationLifecycle()
        _ = lifecycle.restartExpansion()
        _ = lifecycle.advance()
        _ = lifecycle.advance()
        model.presentationState = lifecycle.advance()
        panel.setFrame(targetFrame(size: expandedSize), display: true)
        scheduleExpandedHold()
    }

    private func beginDismissal(duration: TimeInterval, advancesLifecycle: Bool = false) {
        model.presentationState = .dismissing
        let generation = presentationGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.animator().setFrame(
                    targetFrame(size: HUDPanelLayout.compactSize, yOffset: 5),
                    display: true)
            }
        } completionHandler: { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            if advancesLifecycle {
                let next = self.lifecycle.advance()
                self.model.presentationState = next
            }
            self.finishPresentation()
        }
    }

    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        guard model.presentationState == .expanded else { return }
        cancelTransition()
        if !hovering {
            scheduleExpandedHold(after: HUDMotionTokens.hoverExitHold)
        }
    }

    private func resizePanel(for state: HUDPresentationState, duration: TimeInterval) {
        let size = state.usesExpandedGeometry ? expandedSize : HUDPanelLayout.compactSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame(size: size), display: true)
        }
    }

    private var expandedSize: NSSize {
        let snapshot = model.snapshot
        return HUDPanelLayout.expandedSize(
            event: model.event,
            hasBattery: snapshot?.battery.items.isEmpty == false,
            hasMode: snapshot.map {
                $0.noiseControlText != nil || $0.equalizerText != nil
            } ?? false)
    }

    private func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelTransition()
        let generation = presentationGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.transitionWorkItem = nil
            action()
        }
        transitionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelTransition() {
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
    }

    private func finishPresentation() {
        cancelTransition()
        panel.orderOut(nil)
        resetHiddenState()
    }

    private func resetHiddenState() {
        visibleEvent = nil
        presentationVisibleFrame = nil
        isHovering = false
        lifecycle = HUDPresentationLifecycle()
        model.presentationState = .hidden
        panel.alphaValue = 0
    }

    private func pointerScreenVisibleFrame() -> NSRect? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main
        return screen?.visibleFrame
    }

    private func targetFrame(size: NSSize, yOffset: CGFloat = 0) -> NSRect {
        let visibleFrame = presentationVisibleFrame ?? pointerScreenVisibleFrame() ?? panel.frame
        return NSRect(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 22 + yOffset,
            width: size.width,
            height: size.height)
    }
}
