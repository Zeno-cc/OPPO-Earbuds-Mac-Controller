import Carbon.HIToolbox
import Observation
import XCTest
@testable import BudsBar
import BudsCore

/// Coverage for the parts of v1.5 quick control that are pure decisions: shortcut storage and
/// the arbitration between the two non-activating HUDs.
final class QuickControlTests: XCTestCase {

    // MARK: - Hotkey definition

    func testHotKeyModifiersUseCarbonMasks() {
        // RegisterEventHotKey reads Carbon's own bit layout. The earlier 1<<n values were
        // never a real modifier mask, so the shortcut could not have matched a key press.
        XCTAssertEqual(HotKeyDefinition.command, UInt32(cmdKey))
        XCTAssertEqual(HotKeyDefinition.option, UInt32(optionKey))
        XCTAssertEqual(HotKeyDefinition.control, UInt32(controlKey))
        XCTAssertEqual(HotKeyDefinition.shift, UInt32(shiftKey))
        XCTAssertNotEqual(HotKeyDefinition.command, UInt32(1 << 20))
    }

    func testHotKeyRequiresAPrimaryModifier() {
        XCTAssertFalse(HotKeyDefinition(keyCode: 12, modifiers: 0).isValid)
        XCTAssertFalse(HotKeyDefinition(keyCode: 12, modifiers: HotKeyDefinition.shift).isValid)
        XCTAssertTrue(HotKeyDefinition(keyCode: 12, modifiers: HotKeyDefinition.option).isValid)
        XCTAssertTrue(HotKeyDefinition(
            keyCode: 12,
            modifiers: HotKeyDefinition.command | HotKeyDefinition.shift).isValid)
    }

    /// The recorder row only redraws if reading the shortcut registers an observation
    /// dependency. A computed property over a `let` store registers none, which made
    /// "clear" look like it did nothing even though the value was gone from UserDefaults.
    func testHotKeyChangesAreObservableSoTheRecorderRowRedraws() throws {
        let suite = "hotkey.observation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        var setObservations = 0
        withObservationTracking {
            _ = settings.quickNoiseHotKey
        } onChange: {
            setObservations += 1
        }
        settings.setQuickNoiseHotKey(
            HotKeyDefinition(keyCode: 12, modifiers: HotKeyDefinition.option))
        XCTAssertEqual(setObservations, 1, "setting a shortcut must invalidate the row")

        var clearObservations = 0
        withObservationTracking {
            _ = settings.quickNoiseHotKey
        } onChange: {
            clearObservations += 1
        }
        settings.setQuickNoiseHotKey(nil)
        XCTAssertEqual(clearObservations, 1, "clearing must invalidate the row too")
        XCTAssertNil(settings.quickNoiseHotKey)
        XCTAssertNil(HotKeyStore(defaults: defaults).definition)
    }

    func testHotKeyDisplayIsDerivedFromKeyCodeAndModifiers() {
        XCTAssertEqual(
            HotKeyDefinition(keyCode: 12,
                             modifiers: HotKeyDefinition.control | HotKeyDefinition.option)
                .displayText, "⌃⌥Q")
        // Named keys, where the character they type is not their name.
        XCTAssertEqual(KeyCodeNaming.label(for: 36), "↩")
        XCTAssertEqual(KeyCodeNaming.label(for: 53), "⎋")
    }

    // MARK: - HUD slot arbitration

    private func snapshotWithDetails() -> HUDSnapshot {
        HUDSnapshot(
            deviceName: "耳机",
            isConnected: true,
            battery: BatteryPresentation(
                vendor: BatteryState(left: BatteryReading(level: 80)),
                system: BatteryState(),
                placement: EarbudsPlacementState()))
    }

    func testConnectedHUDWaitsWhileTheQuickActionHUDOwnsTheSlot() {
        var slotBusy = true
        let panel = ConnectionHUDPanelController()
        let coordinator = ConnectionHUDCoordinator(
            panelController: panel,
            snapshot: { [self] _ in snapshotWithDetails() },
            isEnabled: { _ in true },
            isSlotBusy: { slotBusy })

        // First observation is the baseline and never presents.
        coordinator.observe(ConnectionExperienceObservation(isConnected: false))
        coordinator.observe(ConnectionExperienceObservation(isConnected: true))
        XCTAssertNil(panel.visibleEvent, "the quick action owns the slot")

        // A later state refresh must not sneak past the busy slot either.
        coordinator.observe(ConnectionExperienceObservation(isConnected: true))
        XCTAssertNil(panel.visibleEvent)

        slotBusy = false
        coordinator.retryDeferredPresentation()
        XCTAssertEqual(panel.visibleEvent, .connected)
    }

    func testConnectedHUDPresentsImmediatelyWhenTheSlotIsFree() {
        let panel = ConnectionHUDPanelController()
        let coordinator = ConnectionHUDCoordinator(
            panelController: panel,
            snapshot: { [self] _ in snapshotWithDetails() },
            isEnabled: { _ in true },
            isSlotBusy: { false })

        coordinator.observe(ConnectionExperienceObservation(isConnected: false))
        coordinator.observe(ConnectionExperienceObservation(isConnected: true))
        XCTAssertEqual(panel.visibleEvent, .connected)

        // Taking the slot for a quick action clears the connection card instead of stacking.
        coordinator.yieldSlot()
        XCTAssertNil(panel.visibleEvent)
    }
}
