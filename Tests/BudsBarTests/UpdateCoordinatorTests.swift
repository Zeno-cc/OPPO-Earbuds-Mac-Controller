import Foundation
import XCTest
@testable import BudsBar

@MainActor
final class UpdateCoordinatorTests: XCTestCase {
    func testOptionalObjectiveCDelegatesAreActuallyImplemented() {
        let coordinator = UpdateCoordinator(bundle: Bundle(for: Self.self))
        for selector in [
            "updater:mayPerformUpdateCheck:error:", "updater:didFindValidUpdate:",
            "updaterDidNotFindUpdate:error:", "updater:didAbortWithError:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:", "feedURLStringForUpdater:",
            "userDidCancelDownload:", "standardUserDriverWillShowModalAlert"
        ] {
            XCTAssertTrue(coordinator.responds(to: NSSelectorFromString(selector)), selector)
        }
    }
    func testUnpackagedBundleDoesNotStartNetworking() {
        let coordinator = UpdateCoordinator(bundle: Bundle(for: Self.self))
        coordinator.start()
        XCTAssertFalse(coordinator.isConfigured)
        XCTAssertFalse(coordinator.canCheckForUpdates)
        if case .unavailable = coordinator.presentation.phase {} else { XCTFail("Expected disabled updater") }
        coordinator.checkForUpdates()
        coordinator.setAutomaticallyChecks(true)
        XCTAssertFalse(coordinator.automaticallyChecks)
    }
}
