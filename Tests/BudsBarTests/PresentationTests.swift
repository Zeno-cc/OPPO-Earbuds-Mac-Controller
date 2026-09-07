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
        XCTAssertFalse(settings.hasSeenWhatsNew(version: "1.3"))

        settings.setConnectHUDEnabled(false)
        settings.setReconnectHUDEnabled(false)
        settings.setUnexpectedDisconnectHUDEnabled(false)
        settings.setMenuBarBatteryEnabled(true)
        settings.setDockIconEnabled(false)
        settings.markWhatsNewSeen(version: "1.3")

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.connectHUDEnabled)
        XCTAssertFalse(restored.reconnectHUDEnabled)
        XCTAssertFalse(restored.unexpectedDisconnectHUDEnabled)
        XCTAssertTrue(restored.menuBarBatteryEnabled)
        XCTAssertFalse(restored.dockIconEnabled)
        XCTAssertTrue(restored.hasSeenWhatsNew(version: "1.3"))
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
}
