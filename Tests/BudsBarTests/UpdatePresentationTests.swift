import Foundation
import Testing
@testable import BudsBar

@Suite struct UpdatePresentationTests {
    @Test func informationalCheckKeepsFoundVersionAfterCycleFinishes() {
        var presentation = UpdatePresentation()
        presentation.begin()
        presentation.found("1.5.2", at: Date(timeIntervalSince1970: 100))
        presentation.finish(hasError: false)

        #expect(presentation.availableVersion == "1.5.2")
        #expect(presentation.phase == .available("1.5.2"))
    }

    @Test func laterKeepsUpdateAvailableForAnotherClick() {
        var presentation = UpdatePresentation()
        presentation.begin()
        presentation.found("1.5.2", at: Date(timeIntervalSince1970: 100))
        presentation.cancel()
        presentation.finish(hasError: true)

        #expect(presentation.availableVersion == "1.5.2")
        #expect(presentation.phase == .available("1.5.2"))
    }

    @Test func skipRemovesTheBlueIndicator() {
        var presentation = UpdatePresentation()
        presentation.begin()
        presentation.found("1.5.2", at: Date(timeIntervalSince1970: 100))
        presentation.skip()
        presentation.finish(hasError: false)

        #expect(presentation.availableVersion == nil)
        #expect(presentation.phase == .idle)
    }

    @Test func freshNoUpdateClearsPreviouslyAvailableVersion() {
        var presentation = UpdatePresentation()
        presentation.found("1.5.2", at: Date(timeIntervalSince1970: 100))
        presentation.begin()
        presentation.noUpdate(at: Date(timeIntervalSince1970: 200))
        presentation.finish(hasError: false)

        #expect(presentation.availableVersion == nil)
        #expect(presentation.phase == .noUpdate)
        #expect(presentation.lastCheckedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func failedCheckCanRetryWithoutForgettingKnownUpdate() {
        var presentation = UpdatePresentation()
        presentation.found("1.5.2", at: Date(timeIntervalSince1970: 100))
        presentation.begin()
        presentation.fail()

        #expect(presentation.phase == .failed)
        #expect(presentation.availableVersion == "1.5.2")
    }
}
