import XCTest
import SwiftUI
@testable import BudsBar
import BudsCore

final class ReducedMotionTests: XCTestCase {
    func testReducedHUDNeverVisitsCompactGeometryDuringItsPresentation() {
        var lifecycle = HUDPresentationLifecycle()
        XCTAssertEqual(lifecycle.start(reduceMotion: true), .expanded)
        XCTAssertEqual(lifecycle.restartExpansion(), .expanded)
        let exit = lifecycle.advance()
        XCTAssertTrue(exit.usesExpandedGeometry)
        XCTAssertTrue(exit.showsBattery)
        XCTAssertTrue(exit.showsMode)
        XCTAssertEqual(lifecycle.advance(), .hidden)
    }

    func testEnablingReducedMotionDuringExpansionAndDismissalKeepsFeedback() {
        var expanding = HUDPresentationLifecycle()
        _ = expanding.start()
        _ = expanding.advance()
        XCTAssertEqual(expanding.enableReducedMotion(), .expanded)
        XCTAssertTrue(expanding.beginDismissal().usesExpandedGeometry)
        var collapsing = HUDPresentationLifecycle()
        _ = collapsing.start()
        for _ in 0..<6 { _ = collapsing.advance() }
        XCTAssertTrue(collapsing.enableReducedMotion().usesExpandedGeometry)
        XCTAssertEqual(collapsing.advance(), .hidden)
    }

    @MainActor
    func testReducedHUDViewRetainsActualGeometryAndContentWhileFading() {
        let model = ConnectionHUDViewModel()
        model.reduceMotion = true
        model.snapshot = HUDSnapshot(deviceName: "OPPO Enco Air5 Pro", isConnected: true,
            battery: BatteryPresentation(vendor: BatteryState(), system: BatteryState(),
                                         placement: EarbudsPlacementState()),
            noiseControlText: "降噪 · 深度")
        let host = NSHostingView(rootView: ConnectionHUDView(model: model))
        model.presentationState = .expanded
        let expanded = host.fittingSize
        model.presentationState = .fadingExpanded
        let fading = host.fittingSize
        XCTAssertEqual(expanded, fading)
        XCTAssertGreaterThan(expanded.width, HUDPanelLayout.compactSize.width)
        XCTAssertGreaterThan(expanded.height, HUDPanelLayout.compactSize.height)
    }
}
