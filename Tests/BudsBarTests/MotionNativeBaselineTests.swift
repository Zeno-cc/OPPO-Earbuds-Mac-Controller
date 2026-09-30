import AppKit
import SwiftUI
import XCTest
import BudsCore
@testable import BudsBar

/// Native window observations; synthetic snapshots never claim radio/hardware acceptance.
final class MotionNativeBaselineTests: XCTestCase {
    private func settle(_ interval: TimeInterval) {
        let deadline = expectation(description: "Native presentation reaches observation point")
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { deadline.fulfill() }
        wait(for: [deadline], timeout: interval + 2)
    }

    @MainActor func testObserveInterruptedAndLateDataHUDGeometry() throws {
        _ = NSApplication.shared
        let controller = ConnectionHUDPanelController()
        defer { controller.dismissImmediately() }
        func snapshot(details: Bool) -> HUDSnapshot {
            HUDSnapshot(deviceName: "OPPO Enco Air5 Pro", isConnected: true,
                battery: BatteryPresentation(vendor: details
                    ? BatteryState(left: .init(level: 80), right: .init(level: 90)) : BatteryState(),
                    system: BatteryState(), placement: EarbudsPlacementState()),
                noiseControlText: details ? "降噪 · 深度" : nil)
        }
        controller.show(event: .connected, snapshot: snapshot(details: false))
        settle(0.40)
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.isVisible && $0.contentViewController is NSHostingController<ConnectionHUDView>
        })
        let model = try XCTUnwrap((window.contentViewController as? NSHostingController<ConnectionHUDView>)?.rootView.model)
        print("Native HUD expanding: panel=\(window.frame.size), state=\(model.presentationState)")
        controller.show(event: .unexpectedDisconnected, snapshot: snapshot(details: false))
        settle(0.50)
        print("Native HUD reversed: panel=\(window.frame.size), host=\(window.contentView?.fittingSize ?? .zero), state=\(model.presentationState)")
        controller.show(event: .reconnected, snapshot: snapshot(details: false))
        settle(0.50)
        controller.update(snapshot: snapshot(details: true))
        settle(0.25)
        print("Native HUD late-data: panel=\(window.frame.size), host=\(window.contentView?.fittingSize ?? .zero), state=\(model.presentationState)")
        XCTAssertEqual(controller.visibleEvent, .reconnected)
        XCTAssertEqual(window.frame.size, HUDPanelLayout.expandedSize(event: .reconnected, hasBattery: true, hasMode: true))
        controller.dismiss()
        settle(0.05)
        controller.show(event: .reconnected, snapshot: snapshot(details: true))
        settle(0.60)
        XCTAssertEqual(controller.visibleEvent, .reconnected, "An old fade completion cannot hide the new event")
        XCTAssertEqual(window.frame.size, HUDPanelLayout.expandedSize(event: .reconnected, hasBattery: true, hasMode: true))
    }
}
