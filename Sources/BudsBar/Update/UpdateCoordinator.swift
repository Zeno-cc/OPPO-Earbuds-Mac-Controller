import AppKit
import Observation
import OSLog
import Sparkle

/// Owns product integration only. Sparkle owns scheduling, trust, download and replacement.
@MainActor @Observable
final class UpdateCoordinator: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var presentation = UpdatePresentation()
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecks = false
    private(set) var isConfigured = false
    let version: String

    @ObservationIgnored var beforePresentingUI: (() -> Void)?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let log = Logger(subsystem: UpdateConfiguration.bundleIdentifier, category: "Updates")

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.version = UpdateConfiguration.versionLabel(bundle.infoDictionary ?? [:])
        super.init()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        guard bundle.bundleURL.pathExtension == "app" else {
            presentation.advance(to: .unavailable("请使用已打包的 App，命令行构建不启动更新。"))
            return
        }
        do { try UpdateConfiguration.validate(bundle.infoDictionary ?? [:]) }
        catch {
            presentation.advance(to: .unavailable("发布者需要配置更新公钥。当前构建不会下载或安装未验证的更新。"))
            log.error("Updater configuration rejected")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        do {
            try controller.updater.start()
            isConfigured = true
            synchronizeSettings()
            observations = [
                controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeSettings() }
                },
                controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeSettings() }
                }
            ]
        } catch {
            self.controller = nil
            presentation.advance(to: .unavailable("无法启动安全更新，请使用官方安装包。"))
            record(error)
        }
    }

    func checkForUpdates() {
        guard let controller, canCheckForUpdates else { return }
        beforePresentingUI?()
        // Only explicit user action activates the app; scheduled checks never call this.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        guard let controller, isConfigured else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        synchronizeSettings()
    }

    private func synchronizeSettings() {
        guard let updater = controller?.updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecks = updater.automaticallyChecksForUpdates
    }

    // Persisted user defaults cannot redirect this production updater to an arbitrary host.
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return UpdateConfiguration.effectiveFeed(bundle.infoDictionary ?? [:], allowTestFeed: true)
        #else
        return UpdateConfiguration.feed
        #endif
    }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { [] }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        presentation.begin()
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        presentation.found(item.displayVersionString, at: Date())
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        presentation.noUpdate(at: Date())
    }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem,
                 with request: NSMutableURLRequest) {
        presentation.advance(to: .downloading(item.displayVersionString))
    }
    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        presentation.advance(to: .verifying(item.displayVersionString))
    }
    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        presentation.advance(to: .verifying(item.displayVersionString))
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        presentation.advance(to: .installing(item.displayVersionString))
    }
    func userDidCancelDownload(_ updater: SPUUpdater) { presentation.cancel() }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        record(error)
        if isCancellation(error) { presentation.cancel() } else { presentation.fail() }
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        if let error, isCancellation(error) { presentation.cancel() }
        presentation.finish(hasError: error != nil)
        synchronizeSettings()
    }

    func standardUserDriverWillShowModalAlert() { beforePresentingUI?() }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                 forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { beforePresentingUI?() }
    }

    private func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == SUSparkleErrorDomain && error.code == Int(SUError.installationCanceledError.rawValue))
    }
    private func record(_ error: Error) {
        let error = error as NSError
        // No release URLs, local paths, device identifiers or arbitrary NSError.userInfo.
        log.notice("Update event: domain=\(error.domain, privacy: .public) code=\(error.code)")
    }
}
