import AppKit
import SwiftUI
import Testing
import BudsCore
@testable import BudsBar

@MainActor @Suite struct HUDContinuityTests {
    @MainActor private final class Harness {
        final class Pointer { var point = NSPoint.zero }
        let clock = TestClock()
        let pointer = Pointer()
        let controller: ConnectionHUDPanelController
        init(reduceMotion: Bool = false) {
            let clock = clock
            let pointer = pointer
            // Mutable preference is captured independently of the controller's lifetime.
            let preference = Preference(reduceMotion)
            self.preference = preference
            controller = ConnectionHUDPanelController(pointerLocation: { pointer.point }, scheduleTransition: { delay, item in
                clock.schedule(after: delay) { if !item.isCancelled { item.perform() } }
            }, shouldReduceMotion: { preference.reduceMotion })
        }
        final class Preference {
            var reduceMotion: Bool
            init(_ reduceMotion: Bool) { self.reduceMotion = reduceMotion }
        }
        let preference: Preference
        var window: NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.contentViewController is NSHostingController<ConnectionHUDView> }
        }
        var model: ConnectionHUDViewModel? {
            (window?.contentViewController as? NSHostingController<ConnectionHUDView>)?.rootView.model
        }
        func show(_ event: ConnectionHUDEvent = .connected) {
            controller.show(event: event, snapshot: Self.snapshot)
        }
        static var snapshot: HUDSnapshot {
            HUDSnapshot(deviceName: "OPPO Enco Air5 Pro", isConnected: true,
                battery: BatteryPresentation(vendor: BatteryState(left: .init(level: 80)),
                    system: BatteryState(), placement: EarbudsPlacementState()), noiseControlText: "降噪")
        }
    }

    @Test func expandedReplacementDoesNotHideDetailsOrChangeScreen() throws {
        let h = Harness()
        defer { h.controller.dismissImmediately() }
        h.show()
        h.clock.advance(by: 1)
        let model = try #require(h.model)
        #expect(model.presentationState == .expanded)
        let anchor = h.window?.frame.maxX
        h.show(.reconnected)
        #expect(model.presentationState == .expanded)
        #expect(model.presentationState.showsBattery && model.presentationState.showsMode)
        #expect(h.window?.frame.maxX == anchor)
        #expect(model.event == .reconnected)
    }

    @Test func identicalSnapshotDoesNotPublishOrExtendReadingDeadline() throws {
        let h = Harness()
        defer { h.controller.dismissImmediately() }
        h.show()
        h.clock.advance(by: 1)
        let model = try #require(h.model)
        var publications = 0
        let observer = model.$snapshot.dropFirst().sink { _ in publications += 1 }
        h.controller.update(snapshot: Harness.snapshot)
        h.clock.advance(by: 2.6)
        #expect(publications == 0)
        #expect(model.presentationState != .expanded)
        withExtendedLifetime(observer) {}
    }

    @Test(arguments: [false, true])
    func replacementFromCollapseDiscardsOldScheduledExit(reduceMotion: Bool) throws {
        let h = Harness(reduceMotion: reduceMotion)
        defer { h.controller.dismissImmediately() }
        h.show()
        h.clock.advance(by: 3.5)
        let model = try #require(h.model)
        #expect(model.presentationState == (reduceMotion ? .fadingExpanded : .collapsing(.content)))
        h.show(.reconnected)
        #expect(model.presentationState == .expanded)
        h.clock.advance(by: 0.8)
        #expect(h.controller.visibleEvent == .reconnected)
        #expect(model.presentationState == .expanded)
    }

    @Test func expandedLifecycleReplacementCanRetainContentWithoutChangingNormalStart() {
        var lifecycle = HUDPresentationLifecycle()
        #expect(lifecycle.start() == .compact)
        #expect(lifecycle.restartExpansion(preservingExpandedContent: true) == .expanded)
        #expect(lifecycle.advance() == .collapsing(.content))
        #expect(lifecycle.start(reduceMotion: true) == .expanded)
        #expect(lifecycle.restartExpansion(preservingExpandedContent: true) == .expanded)
        #expect(lifecycle.advance() == .fadingExpanded)
    }

    @Test(arguments: [false, true])
    func stationaryHoverSurvivesReplacementUntilActualExit(reduceMotion: Bool) throws {
        let h = Harness(reduceMotion: reduceMotion)
        defer { h.controller.dismissImmediately() }
        h.show()
        h.clock.advance(by: 1)
        let window = try #require(h.window)
        let model = try #require(h.model)
        h.pointer.point = NSPoint(x: window.frame.midX, y: window.frame.midY)
        model.onHoverChange?(true)
        #expect(model.isHovered)
        h.show(.reconnected)
        #expect(model.isHovered)
        h.clock.advance(by: 10)
        #expect(model.presentationState == .expanded)
        #expect(h.controller.visibleEvent == .reconnected)
        model.onHoverChange?(false)
        h.clock.advance(by: HUDMotionTokens.hoverExitHold)
        #expect(model.presentationState == (reduceMotion ? .fadingExpanded : .collapsing(.content)))
    }

    @Test func preferenceChangeDuringExpansionConvergesAtSameTargetFrame() throws {
        let h = Harness()
        defer { h.controller.dismissImmediately() }
        h.show()
        h.clock.advance(by: HUDMotionTokens.compactEnter + HUDMotionTokens.compactHold)
        let window = try #require(h.window)
        let model = try #require(h.model)
        #expect(model.presentationState == .expanding(.container))
        h.preference.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(model.reduceMotion)
        #expect(model.presentationState == .expanded)
        #expect(window.frame.size == HUDPanelLayout.expandedSize(event: .connected, hasBattery: true, hasMode: true))
        h.show(.reconnected)
        #expect(model.reduceMotion && model.presentationState == .expanded)
    }

    @Test func replacementRechecksPointerAndHiddenResetClearsHover() throws {
        let h = Harness()
        h.show()
        h.clock.advance(by: 1)
        let window = try #require(h.window)
        let model = try #require(h.model)
        h.pointer.point = NSPoint(x: window.frame.midX, y: window.frame.midY)
        model.onHoverChange?(true)
        h.pointer.point = .zero
        h.show(.reconnected)
        #expect(!model.isHovered)
        h.controller.dismissImmediately()
        #expect(!model.isHovered)
        #expect(h.controller.visibleEvent == nil)
    }
}
