import BudsCore
import XCTest
import SwiftUI
@testable import BudsBar

final class PresentationTests: XCTestCase {
    func testRepositoryFooterOpensOnlyTheProjectPage() {
        XCTAssertEqual(RepositoryDestination.url.absoluteString,
                       "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller")
        XCTAssertEqual(RepositoryDestination.footerHeight, 54)
    }

    /// A fixed-height release panel clipped the added v1.5 rows into "…". The panel must be
    /// sized from its content, so adding a feature can never hide one.
    func testWhatsNewPanelIsTallEnoughForItsContent() {
        let hosting = NSHostingController(rootView: WhatsNewView {})
        hosting.sizingOptions = [.preferredContentSize]
        let neededHeight = hosting.view.fittingSize.height

        let controller = WhatsNewPanelController()
        XCTAssertGreaterThan(neededHeight, 0, "the view must report an intrinsic height")
        XCTAssertGreaterThanOrEqual(
            controller.contentSize.height, neededHeight - 1,
            "panel height \(controller.contentSize.height) clips content of \(neededHeight)")
        XCTAssertGreaterThanOrEqual(
            controller.contentSize.width, WhatsNewView.contentWidth)
    }

    @MainActor
    func testRepositoryFooterRendersAtPanelWidthInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = RepositoryFooter().frame(width: PanelDesignTokens.width)
                .background(scheme == .light ? Color.white : Color.black)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, Int(PanelDesignTokens.width * 2))
            XCTAssertEqual(image.height, Int(RepositoryDestination.footerHeight * 2))
            if let directory = ProcessInfo.processInfo.environment["EQ_FOOTER_PREVIEW_DIR"] {
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("footer-\(scheme).png"))
            }
        }
    }

    @MainActor
    func testEQSliderUsesThirteenDiscreteVerticalSteps() {
        let slider = EQBandSlider.makeSlider()
        XCTAssertTrue(slider.isVertical)
        XCTAssertEqual(slider.minValue, -6)
        XCTAssertEqual(slider.maxValue, 6)
        XCTAssertEqual(slider.numberOfTickMarks, 13)
        XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        XCTAssertTrue(slider.isContinuous)
    }

    func testEQGainLabelsAndFrequencyLabelsAreCompact() {
        XCTAssertEqual(EQEditorDesign.gainLabel(6), "+6")
        XCTAssertEqual(EQEditorDesign.gainLabel(-6), "−6")
        XCTAssertEqual(EQEditorDesign.gainLabel(0), "0")
        XCTAssertEqual(CustomEqualizer.bandFrequencies.map(EQEditorDesign.frequencyLabel),
                       ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"])
    }

    @MainActor
    func testCustomEQHostDoesNotDriveWindowSizeFromChangingContent() {
        _ = NSApplication.shared
        let host = CustomEqualizerPanelController.makeHost(rootView: Text("正在读取…"))
        XCTAssertTrue(host.sizingOptions.isEmpty,
                      "Dynamic EQ content must not create window/intrinsic-size feedback")
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 660),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 350, height: 660))
        let originalSize = panel.frame.size
        for text in ["正在读取…", String(repeating: "频段 0 dB\n", count: 10), "读取失败"] {
            host.rootView = Text(text)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.layoutIfNeeded()
            XCTAssertEqual(panel.frame.size, originalSize)
        }
        panel.close()
    }

    func testPopoverContentNeverPresentsModalSheets() throws {
        // Architecture regression: a sheet on the status NSPopover can leave its
        // controls blocked when the popover closes. Editors must use independent panels.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/BudsBar")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources,
            includingPropertiesForKeys: nil))
        let modal = try NSRegularExpression(pattern: #"\.(sheet|fullScreenCover)\s*\("#)
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertEqual(modal.numberOfMatches(in: source,
                range: NSRange(source.startIndex..., in: source)), 0,
                "Use a non-modal NSPanel, not a sheet in \(file.lastPathComponent)")
        }
    }

    func testDeviceInformationRefreshFeedbackAdvancesOnlyForEnqueuedRequest() {
        XCTAssertEqual(
            DeviceInformationRefreshFeedback.nextTrigger(current: 2, didEnqueue: true),
            3)
        XCTAssertEqual(
            DeviceInformationRefreshFeedback.nextTrigger(current: 2, didEnqueue: false),
            2)
    }

    func testWhatsNewPanelCentersWithinVisibleScreenFrame() {
        let visibleFrame = NSRect(x: 1_440, y: 24, width: 1_920, height: 1_056)
        let panelSize = NSSize(width: 400, height: 360)

        let origin = WhatsNewPanelPositioning.centeredOrigin(
            panelSize: panelSize,
            visibleFrame: visibleFrame)

        XCTAssertEqual(origin.x, 2_200)
        XCTAssertEqual(origin.y, 372)
    }

    func testWhatsNewPresentationIsRequestedOnlyOncePerVersion() throws {
        let suite = "PresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(WhatsNewPresentationPolicy.requestIfNeeded(version: "1.3", settings: settings))
        XCTAssertTrue(settings.hasSeenWhatsNew(version: "1.3"))
        XCTAssertFalse(WhatsNewPresentationPolicy.requestIfNeeded(version: "1.3", settings: settings))
        XCTAssertTrue(WhatsNewPresentationPolicy.requestIfNeeded(version: "1.4", settings: settings))
    }

    func testDelightPreferencesHaveProductDefaultsAndPersistChanges() throws {
        let suite = "PresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.connectHUDEnabled)
        XCTAssertTrue(settings.reconnectHUDEnabled)
        XCTAssertTrue(settings.unexpectedDisconnectHUDEnabled)
        XCTAssertFalse(settings.menuBarBatteryEnabled)
        XCTAssertTrue(settings.dockIconEnabled)
        XCTAssertFalse(settings.hasSeenWhatsNew(version: "1.4"))

        settings.setConnectHUDEnabled(false)
        settings.setReconnectHUDEnabled(false)
        settings.setUnexpectedDisconnectHUDEnabled(false)
        settings.setMenuBarBatteryEnabled(true)
        settings.setDockIconEnabled(false)
        settings.markWhatsNewSeen(version: "1.4")

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.connectHUDEnabled)
        XCTAssertFalse(restored.reconnectHUDEnabled)
        XCTAssertFalse(restored.unexpectedDisconnectHUDEnabled)
        XCTAssertTrue(restored.menuBarBatteryEnabled)
        XCTAssertFalse(restored.dockIconEnabled)
        XCTAssertTrue(restored.hasSeenWhatsNew(version: "1.4"))
    }

    func testMenuBarRemainsReachableWhenDockIconIsHidden() {
        XCTAssertTrue(
            AppVisibilityPolicy.shouldShowMenuBarItem(
                isDeviceAvailable: false,
                dockIconEnabled: false))
        XCTAssertFalse(
            AppVisibilityPolicy.shouldShowMenuBarItem(
                isDeviceAvailable: false,
                dockIconEnabled: true))
        XCTAssertTrue(
            AppVisibilityPolicy.shouldShowMenuBarItem(
                isDeviceAvailable: true,
                dockIconEnabled: true))
    }

    func testBatteryPresentationPrefersVendorSlotsAndKeepsCase() {
        let presentation = BatteryPresentation(
            vendor: BatteryState(
                left: BatteryReading(level: 84, isCharging: false),
                enclosure: BatteryReading(level: 61, isCharging: true)),
            system: BatteryState(
                left: BatteryReading(level: 70),
                right: BatteryReading(level: 73),
                enclosure: BatteryReading(level: 55),
                combined: BatteryReading(level: 72)),
            placement: EarbudsPlacementState())

        XCTAssertEqual(presentation.items.map(\.kind), [.left, .right, .enclosure])
        XCTAssertEqual(presentation.items.map(\.reading.level), [84, 73, 61])
        XCTAssertEqual(presentation.menuBarPercentage, 73)
    }

    func testAggregateBatteryIsShownOnlyAsHeadphones() {
        let presentation = BatteryPresentation(
            vendor: BatteryState(),
            system: BatteryState(combined: BatteryReading(level: 80)),
            placement: EarbudsPlacementState())

        XCTAssertEqual(presentation.items.map(\.kind), [.combined])
        XCTAssertEqual(presentation.items.first?.label, "耳机")
        XCTAssertNil(presentation.menuBarPercentage)
    }

    func testEarStateIsIndependentOfBatteryAndDoesNotClaimWornOrCharging() {
        let state = EarStatePresentation(placement: EarbudsPlacementState(
            left: .inCase, right: .inUse))
        XCTAssertEqual(state.left, "左耳 · 盒内")
        XCTAssertEqual(state.right, "右耳 · 盒外")
        let unknown = EarStatePresentation(placement: EarbudsPlacementState())
        XCTAssertNil(unknown.left)
        XCTAssertNil(unknown.right)
    }

    func testMenuBarBatteryRequiresTwoIndependentValidReadings() {
        let oneSide = BatteryPresentation(
            vendor: BatteryState(left: BatteryReading(level: 42)),
            system: BatteryState(combined: BatteryReading(level: 90)),
            placement: EarbudsPlacementState())
        let invalidSide = BatteryPresentation(
            vendor: BatteryState(
                left: BatteryReading(level: 42),
                right: BatteryReading(level: 101)),
            system: BatteryState(),
            placement: EarbudsPlacementState())

        XCTAssertNil(oneSide.menuBarPercentage)
        XCTAssertNil(invalidSide.menuBarPercentage)
    }

    func testMenuBarBatteryStartsIconOnlyWithoutTrustedSlotObservation() {
        // The projection only accepts per-slot vendor observations, so an aggregate-only
        // state has nothing to show and must stay icon-only instead of inventing L/R.
        XCTAssertNil(MenuBarBatteryPresentation(
            observations: [:], generation: 1, now: 0).text)

        // Explicit unknown and a stale reading are both "no displayable slot".
        XCTAssertNil(MenuBarBatteryPresentation(observations: [
            .left: BatterySlotObservation(reading: nil, generation: 1, observedAt: 0)
        ], generation: 1, now: 0).text)
        XCTAssertNil(MenuBarBatteryPresentation(observations: [
            .left: BatterySlotObservation(
                reading: BatteryReading(level: 42), generation: 1, observedAt: 0)
        ], generation: 1, now: 46).text)
    }

    func testMenuBarBatteryDropsObservationsFromAnEarlierGeneration() {
        let presentation = MenuBarBatteryPresentation(observations: [
            .left: BatterySlotObservation(
                reading: BatteryReading(level: 80), generation: 1, observedAt: 0),
            .right: BatterySlotObservation(
                reading: BatteryReading(level: 81), generation: 2, observedAt: 0)
        ], generation: 2, now: 0)
        XCTAssertEqual(presentation.text, "L —  R 81%  C —")
    }

    func testMenuBarBatteryKeepsPartialFreshSlotsAndMarksStaleOrUnknownAsDash() {
        let presentation = MenuBarBatteryPresentation(observations: [
            .left: BatterySlotObservation(reading: BatteryReading(level: 0), generation: 1, observedAt: 40),
            .right: BatterySlotObservation(reading: BatteryReading(level: 72), generation: 1, observedAt: 0),
            .enclosure: BatterySlotObservation(reading: nil, generation: 1, observedAt: 40)
        ], generation: 1, now: 46)
        XCTAssertEqual(presentation.text, "L 0%  R —  C —")
        XCTAssertTrue(presentation.tooltip?.contains("左耳 0%") == true)
        XCTAssertTrue(presentation.tooltip?.contains("右耳 未知") == true)
    }

    func testMenuBarBatteryOnlyShowsLightningForExplicitChargingTrue() {
        let presentation = MenuBarBatteryPresentation(observations: [
            .left: BatterySlotObservation(reading: BatteryReading(level: 50, isCharging: false), generation: 1, observedAt: 0),
            .right: BatterySlotObservation(reading: BatteryReading(level: 51, isCharging: nil), generation: 1, observedAt: 0),
            .enclosure: BatterySlotObservation(reading: BatteryReading(level: 52, isCharging: true), generation: 1, observedAt: 0)
        ], generation: 1, now: 0)
        XCTAssertEqual(presentation.text, "L 50%  R 51%  C 52% ⚡")
    }

    func testQuickNoiseToggleWaitsOnceForUnknownAndCancelsExpiredIntent() {
        var state = QuickNoiseState()
        XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 3, now: 10), .waitForMode)
        XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 3, now: 10.5), .waitForMode)
        XCTAssertEqual(QuickNoiseReducer.modeArrived(&state, mode: .transparency, generation: 3, now: 12.1), .ignored)
        XCTAssertFalse(state.isWaitingForMode)
    }

    func testQuickNoiseToggleUsesTransparencyAndANCWithoutOptimism() {
        var state = QuickNoiseState(confirmedMode: .noiseCancellation)
        XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 1, now: 0), .send(.transparency))
        state.confirmedMode = .off
        XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 1, now: 0), .send(.noiseCancellation))
        XCTAssertFalse(state.operationPending)
    }

    /// The intent must invert the mode the buds actually report, not a target decided while
    /// that mode was still unknown — otherwise an unknown-mode press whose report says ANC
    /// would send ANC again and look successful.
    func testDeferredQuickToggleInvertsTheModeThatActuallyArrives() {
        for arrived in NoiseMode.allCases {
            var state = QuickNoiseState()
            XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 7, now: 0), .waitForMode)
            XCTAssertEqual(
                QuickNoiseReducer.modeArrived(&state, mode: arrived, generation: 7, now: 1.5),
                .send(QuickNoiseReducer.target(for: arrived)))
            XCTAssertFalse(state.isWaitingForMode)
        }
    }

    /// After the window closes the entry point must work again, not stay silent forever.
    func testExpiredIntentIsReArmedByTheNextToggle() {
        var state = QuickNoiseState()
        XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 5, now: 0), .waitForMode)
        XCTAssertFalse(QuickNoiseReducer.hasLiveIntent(state, generation: 5, now: 2.5))
        XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 5, now: 3), .waitForMode)
        XCTAssertTrue(QuickNoiseReducer.hasLiveIntent(state, generation: 5, now: 3.5))
        // A report for the stale window does not fire; the re-armed one still does.
        XCTAssertEqual(QuickNoiseReducer.modeArrived(&state, mode: .transparency, generation: 5, now: 3.6),
                       .send(.noiseCancellation))
    }

    func testIntentFromAnEarlierGenerationIsNeverResolved() {
        var state = QuickNoiseState()
        XCTAssertEqual(QuickNoiseReducer.toggle(&state, generation: 1, now: 0), .waitForMode)
        XCTAssertEqual(QuickNoiseReducer.modeArrived(&state, mode: .off, generation: 2, now: 1), .ignored)
        XCTAssertFalse(state.isWaitingForMode)
    }

    func testHotKeyRequiresPrimaryModifierAndPersistsAsTwoValues() throws {
        XCTAssertFalse(HotKeyDefinition(keyCode: 12, modifiers: 0).isValid)
        let suite = "hotkey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let definition = HotKeyDefinition(keyCode: 12, modifiers: HotKeyDefinition.option)
        HotKeyStore(defaults: defaults).save(definition)
        XCTAssertEqual(HotKeyStore(defaults: defaults).definition, definition)
        HotKeyStore(defaults: defaults).save(nil)
        XCTAssertNil(HotKeyStore(defaults: defaults).definition)
    }
}
