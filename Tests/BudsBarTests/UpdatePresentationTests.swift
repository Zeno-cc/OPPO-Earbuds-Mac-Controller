import Foundation
import XCTest
@testable import BudsBar

final class UpdatePresentationTests: XCTestCase {
    func testInitialState() {
        XCTAssertEqual(UpdatePresentation().phase, .idle)
        XCTAssertNil(UpdatePresentation().lastCheckedAt)
    }
    func testNoUpdateErrorIsNotAConnectionFailure() {
        var model = UpdatePresentation()
        model.begin()
        model.noUpdate(at: Date(timeIntervalSince1970: 10))
        model.fail()
        model.finish(hasError: true)
        XCTAssertEqual(model.phase, .noUpdate)
        XCTAssertEqual(model.lastCheckedAt, Date(timeIntervalSince1970: 10))
    }
    func testNewCycleClearsPreviousDisposition() {
        var model = UpdatePresentation()
        model.noUpdate(at: Date())
        model.begin()
        model.fail()
        XCTAssertEqual(model.phase, .failed)
    }
    func testDownloadLifecycle() {
        var model = UpdatePresentation()
        model.begin()
        model.found("1.5.2", at: Date())
        XCTAssertEqual(model.phase, .available("1.5.2"))
        model.advance(to: .downloading("1.5.2"))
        XCTAssertTrue(model.phase.isBusy)
        model.advance(to: .verifying("1.5.2"))
        XCTAssertTrue(model.phase.isBusy)
        model.advance(to: .readyToInstall("1.5.2"))
        model.finish(hasError: false)
        XCTAssertEqual(model.phase, .readyToInstall("1.5.2"))
    }
    func testDismissedOfferClearsStaleBadge() {
        var model = UpdatePresentation()
        model.found("1.5.2", at: Date())
        model.finish(hasError: false)
        XCTAssertEqual(model.phase, .idle)
    }
    func testCancellationRemainsQuiet() {
        var model = UpdatePresentation()
        model.begin()
        model.cancel()
        model.fail()
        model.finish(hasError: true)
        XCTAssertEqual(model.phase, .idle)
    }
    func testFailureDoesNotClaimSuccessfulCheckTime() {
        var model = UpdatePresentation()
        model.begin()
        model.fail()
        XCTAssertNil(model.lastCheckedAt)
    }
    func testStatesHaveAccessibleCopy() {
        let states: [AppUpdatePhase] = [.idle, .checking, .noUpdate, .available("1.5.2"),
            .downloading("1.5.2"), .verifying("1.5.2"), .readyToInstall("1.5.2"),
            .installing("1.5.2"), .failed, .unavailable("未配置")]
        for state in states {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.detail.isEmpty)
        }
    }
    func testVersionUsesBundleMetadata() {
        XCTAssertEqual(UpdateConfiguration.versionLabel(["CFBundleShortVersionString": "1.5.1"]), "v1.5.1")
        XCTAssertNotEqual(UpdateConfiguration.versionLabel([:]), "v1.5.1")
    }
}

final class UpdateConfigurationTests: XCTestCase {
    private var valid: [String: Any] {
        ["CFBundleIdentifier": UpdateConfiguration.bundleIdentifier,
         "SUFeedURL": UpdateConfiguration.feed,
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
         "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
         "SUSignedFeedFailureExpirationInterval": 0,
         "SUAllowsAutomaticUpdates": false, "SUAutomaticallyUpdate": false]
    }
    func testValidConfiguration() { XCTAssertNoThrow(try UpdateConfiguration.validate(valid)) }
    func testMissingKeyFailsClosed() {
        var info = valid
        info.removeValue(forKey: "SUPublicEDKey")
        XCTAssertThrowsError(try UpdateConfiguration.validate(info))
    }
    func testMalformedOrZeroKeysFailClosed() {
        for key in ["TODO", "", Data(repeating: 0, count: 32).base64EncodedString(),
                    Data(repeating: 1, count: 31).base64EncodedString()] {
            var info = valid
            info["SUPublicEDKey"] = key
            XCTAssertThrowsError(try UpdateConfiguration.validate(info))
        }
    }
    func testOnlyOfficialFeedIsAccepted() {
        for url in ["http://github.com/appcast.xml", "https://example.com/appcast.xml",
                    UpdateConfiguration.feed + "?mirror=1", "file:///tmp/appcast.xml"] {
            var info = valid
            info["SUFeedURL"] = url
            XCTAssertThrowsError(try UpdateConfiguration.validate(info))
        }
    }
    func testIdentityCannotChange() {
        var info = valid
        info["CFBundleIdentifier"] = "unrelated.app"
        XCTAssertThrowsError(try UpdateConfiguration.validate(info))
    }
    func testBothSignatureChecksAreRequired() {
        for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"] {
            var info = valid
            info[key] = false
            XCTAssertThrowsError(try UpdateConfiguration.validate(info))
        }
    }
    func testSignatureFailureCannotExpire() {
        var info = valid
        info["SUSignedFeedFailureExpirationInterval"] = 1728000
        XCTAssertThrowsError(try UpdateConfiguration.validate(info))
    }
    func testUnattendedInstallIsDisabled() {
        for key in ["SUAllowsAutomaticUpdates", "SUAutomaticallyUpdate"] {
            var info = valid
            info[key] = true
            XCTAssertThrowsError(try UpdateConfiguration.validate(info))
        }
    }
    func testProductionIgnoresTestFeed() {
        XCTAssertEqual(UpdateConfiguration.effectiveFeed([
            "BudsBarUpdateTestBuild": true, "BudsBarTestFeedURL": "http://localhost:8765/appcast.xml"]),
            UpdateConfiguration.feed)
    }
    func testMarkedDebugMayUseLoopbackFeed() {
        let url = "http://localhost:8765/appcast.xml"
        XCTAssertEqual(UpdateConfiguration.effectiveFeed([
            "BudsBarUpdateTestBuild": true, "BudsBarTestFeedURL": url], allowTestFeed: true), url)
    }
    func testUnmarkedOrRemoteTestFeedRejected() {
        for info: [String: Any] in [
            ["BudsBarTestFeedURL": "http://localhost:8765/appcast.xml"],
            ["BudsBarUpdateTestBuild": true, "BudsBarTestFeedURL": "https://bad.example/appcast.xml"],
            ["BudsBarUpdateTestBuild": true, "BudsBarTestFeedURL": "http://user@localhost:8765/appcast.xml"]
        ] {
            XCTAssertEqual(UpdateConfiguration.effectiveFeed(info, allowTestFeed: true), UpdateConfiguration.feed)
        }
    }
}
