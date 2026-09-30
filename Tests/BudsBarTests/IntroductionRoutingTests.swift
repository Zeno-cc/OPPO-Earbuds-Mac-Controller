import Foundation
import Testing
import BudsCore
@testable import BudsBar

@MainActor @Suite struct IntroductionRoutingTests {
    private final class Transport: ControlTransport {
        var eventHandler: ((ControlTransportEvent) -> Void)?
        var isOpen = false
        func open() {}
        func close() {}
        func send(_ bytes: [UInt8]) -> Bool { false }
    }

    @Test func firstEntryOwnsIntroductionNextEntryCanOpenControls() throws {
        let suite = "IntroductionRouting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.markWhatsNewSeen(version: "1.5")
        let session = EarbudsSession(profile: .encoAir5Pro, transport: Transport())
        let buds = Buds(session: session, now: { 0 }, scheduleTimeout: { _,_ in }, settings: settings)
        var introductions = 0
        var feedbackDismissals = 0
        buds.onWhatsNewRequested = { introductions += 1 }
        buds.onQuickActionFeedbackDismissed = { feedbackDismissals += 1 }
        #expect(buds.panelWillOpen())
        #expect(introductions == 1)
        #expect(WhatsNewView.version == "1.6")
        #expect(settings.hasSeenWhatsNew(version: "1.6"))
        #expect(!buds.panelWillOpen())
        #expect(introductions == 1)
        #expect(feedbackDismissals == 2)
        buds.showWhatsNew()
        #expect(introductions == 2, "Manual introduction remains available after first entry")
    }
}
