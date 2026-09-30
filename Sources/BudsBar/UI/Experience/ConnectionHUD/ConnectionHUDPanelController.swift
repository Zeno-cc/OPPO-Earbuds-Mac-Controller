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
    @Published var reduceMotion = false
    @Published var isHovered = false
    var onHoverChange: ((Bool) -> Void)?
}

final class ConnectionHUDPanelController: NSObject {
    private let panel: NSPanel
    private let model = ConnectionHUDViewModel()
    private var lifecycle = HUDPresentationLifecycle()
    private var transitionWorkItem: DispatchWorkItem?
    private var presentationGeneration = 0
    private var presentationVisibleFrame: NSRect?
    private var isHovering: Bool { model.isHovered }
    private var lastTargetFrame: NSRect?
    private let pointerLocation: () -> NSPoint
    private let scheduleTransition: (TimeInterval, DispatchWorkItem) -> Void
    private var expandedHoldDeadline: Date?
    private(set) var visibleEvent: ConnectionHUDEvent?

    override convenience init() {
        self.init(pointerLocation: { NSEvent.mouseLocation }, scheduleTransition: {
            DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
        })
    }

    init(pointerLocation: @escaping () -> NSPoint,
         scheduleTransition: @escaping (TimeInterval, DispatchWorkItem) -> Void) {
        self.pointerLocation = pointerLocation
        self.scheduleTransition = scheduleTransition
        panel = ConnectionHUDPanel(
            contentRect: NSRect(origin: .zero, size: HUDPanelLayout.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        super.init()
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
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func show(event: ConnectionHUDEvent, snapshot: HUDSnapshot) {
        let wasVisible = panel.isVisible
        let previousState = model.presentationState
        presentationGeneration += 1
        cancelTransition()
        model.event = event
        model.snapshot = snapshot
        visibleEvent = event
        model.isHovered = wasVisible && model.isHovered && panel.frame.contains(pointerLocation())

        if wasVisible {
            continueWithNewEvent(from: previousState)
        } else {
            beginPresentation()
        }
    }

    func update(snapshot: HUDSnapshot) {
        guard visibleEvent != nil, model.snapshot != snapshot else { return }
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
        beginDismissal(duration: lifecycle.reduceMotion
            ? HUDMotionTokens.reducedTransition : HUDMotionTokens.dismiss)
    }

    /// Hands the shared slot over without a fade. Used when a user-triggered HUD needs the
    /// slot now: an animating card would still overlap it for the length of the dismissal.
    func dismissImmediately() {
        presentationGeneration += 1
        finishPresentation()
    }

    private func beginPresentation() {
        lifecycle = HUDPresentationLifecycle()
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.presentationState = lifecycle.start(reduceMotion: model.reduceMotion)
        if model.event != .unexpectedDisconnected {
            model.connectedPulseTrigger += 1
        }
        presentationVisibleFrame = pointerScreenVisibleFrame()

        let reduceMotion = lifecycle.reduceMotion
        let size = reduceMotion ? expandedSize : HUDPanelLayout.compactSize
        expandedHoldDeadline = Date().addingTimeInterval(
            (reduceMotion ? HUDMotionTokens.reducedTransition
                : HUDMotionTokens.compactEnter + HUDMotionTokens.compactHold
                    + HUDMotionTokens.batteryRevealDelay + HUDMotionTokens.modeRevealDelay
                    + HUDMotionTokens.expandSettle) + HUDMotionTokens.expandedHold)
        panel.alphaValue = 0
        let entryOffset: CGFloat = reduceMotion ? 0 : 10
        panel.setFrame(
            targetFrame(size: size, yOffset: entryOffset),
            display: false)
        lastTargetFrame = targetFrame(size: size)
        panel.contentView?.layoutSubtreeIfNeeded()
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
            scheduleExpandedHold(after: HUDMotionTokens.reducedTransition + HUDMotionTokens.expandedHold)
        } else {
            scheduleAdvance(after: HUDMotionTokens.compactEnter + HUDMotionTokens.compactHold)
        }
    }

    private func continueWithNewEvent(from previousState: HUDPresentationState) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionTokens.fast
            panel.animator().alphaValue = 1
        }
        lifecycle = HUDPresentationLifecycle()
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        _ = lifecycle.start(reduceMotion: model.reduceMotion)
        let state = lifecycle.restartExpansion(preservingExpandedContent:
            previousState.usesExpandedGeometry && previousState != .expanding(.container))
        model.presentationState = state

        if state == .expanded {
            resizePanel(for: state, duration: MotionTokens.standard)
            scheduleExpandedHold()
        } else {
            expandedHoldDeadline = Date().addingTimeInterval(
                HUDMotionTokens.batteryRevealDelay + HUDMotionTokens.modeRevealDelay
                    + HUDMotionTokens.expandSettle + HUDMotionTokens.expandedHold)
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
        case .fadingExpanded:
            beginDismissal(duration: HUDMotionTokens.reducedTransition, advancesLifecycle: true)
        case .hidden:
            finishPresentation()
        case .compact:
            scheduleAdvance(after: HUDMotionTokens.compactEnter + HUDMotionTokens.compactHold)
        }
    }

    private func scheduleExpandedHold(after delay: TimeInterval = HUDMotionTokens.expandedHold) {
        guard !isHovering else { return }
        expandedHoldDeadline = Date().addingTimeInterval(delay)
        scheduleAdvance(after: delay)
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        guard panel.isVisible, !lifecycle.reduceMotion,
              NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // Invalidate any old fade completion before replacing an in-flight frame animation.
        presentationGeneration += 1
        cancelTransition()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.reduceMotion = true
            model.presentationState = lifecycle.enableReducedMotion()
        }
        // Preference changes must stop an in-flight frame animation even at the same target.
        lastTargetFrame = nil
        resizePanel(for: model.presentationState, duration: 0)
        if model.presentationState == .fadingExpanded {
            beginDismissal(duration: HUDMotionTokens.reducedTransition)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = HUDMotionTokens.reducedTransition
                panel.animator().alphaValue = 1
            }
            let remaining = expandedHoldDeadline.map { max(0, $0.timeIntervalSinceNow) }
                ?? HUDMotionTokens.expandedHold
            scheduleExpandedHold(after: remaining)
        }
    }

    private func beginDismissal(duration: TimeInterval, advancesLifecycle: Bool = false) {
        model.presentationState = lifecycle.beginDismissal()
        let generation = presentationGeneration
        let exitFrame = targetFrame(size: HUDPanelLayout.compactSize, yOffset: 5)
        if !lifecycle.reduceMotion { lastTargetFrame = exitFrame }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if !lifecycle.reduceMotion {
                panel.animator().setFrame(
                    exitFrame,
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
        guard model.isHovered != hovering else { return }
        model.isHovered = hovering
        guard model.presentationState == .expanded else { return }
        cancelTransition()
        expandedHoldDeadline = nil
        if !hovering {
            scheduleExpandedHold(after: HUDMotionTokens.hoverExitHold)
        }
    }

    private func resizePanel(for state: HUDPresentationState, duration: TimeInterval) {
        let size = state.usesExpandedGeometry ? expandedSize : HUDPanelLayout.compactSize
        let frame = targetFrame(size: size)
        guard frame != lastTargetFrame else { return }
        lastTargetFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = lifecycle.reduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
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
        scheduleTransition(delay, work)
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
        model.isHovered = false
        lastTargetFrame = nil
        expandedHoldDeadline = nil
        lifecycle = HUDPresentationLifecycle()
        model.presentationState = .hidden
        panel.alphaValue = 0
    }

    private func pointerScreenVisibleFrame() -> NSRect? {
        let point = pointerLocation()
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
