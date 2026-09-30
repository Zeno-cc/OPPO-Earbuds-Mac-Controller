import Foundation

enum AppUpdatePhase: Equatable {
    case idle, checking, noUpdate, available(String), downloading(String), verifying(String)
    case readyToInstall(String), installing(String), failed, unavailable(String)

    var title: String {
        switch self {
        case .idle: return "随时保持最新"
        case .checking: return "正在检查更新…"
        case .noUpdate: return "暂无可安装的更新"
        case .available(let version): return "v\(version) 可以更新"
        case .downloading(let version): return "正在下载 v\(version)"
        case .verifying: return "正在验证更新…"
        case .readyToInstall(let version): return "v\(version) 已准备就绪"
        case .installing: return "正在安装更新…"
        case .failed: return "更新未完成"
        case .unavailable: return "此构建未启用安全更新"
        }
    }

    var detail: String {
        switch self {
        case .unavailable(let reason): return reason
        case .failed: return "请稍后重试。当前版本仍可正常使用。"
        case .checking: return "正在连接官方更新源，不影响耳机控制。"
        case .downloading, .verifying, .readyToInstall, .installing:
            return "请在更新窗口中继续；设置和 Mac 本地 EQ 方案会保留。"
        default: return "更新包经签名验证，确认后再安装并重启。"
        }
    }

    var isBusy: Bool {
        switch self { case .checking, .downloading, .verifying, .installing: return true; default: return false }
    }
}

struct UpdatePresentation: Equatable {
    private(set) var phase: AppUpdatePhase = .idle
    private(set) var lastCheckedAt: Date?
    private(set) var availableVersion: String?
    private var receivedNoUpdate = false
    private var cancelled = false

    /// Busy has a progress slot; errors outrank a previously discovered version.
    func buttonSymbol(showsNoUpdateCheck: Bool) -> String? {
        if phase.isBusy { return nil }
        if case .failed = phase { return "exclamationmark.circle" }
        if availableVersion != nil { return "arrow.down.circle.fill" }
        if showsNoUpdateCheck { return "checkmark.circle" }
        return "arrow.down.circle"
    }

    mutating func begin() { receivedNoUpdate = false; cancelled = false; phase = .checking }
    mutating func found(_ version: String, at date: Date) {
        availableVersion = version
        lastCheckedAt = date
        phase = .available(version)
    }
    mutating func noUpdate(at date: Date) {
        receivedNoUpdate = true
        availableVersion = nil
        lastCheckedAt = date
        phase = .noUpdate
    }
    mutating func advance(to next: AppUpdatePhase) { phase = next }
    mutating func cancel() {
        cancelled = true
        phase = availableVersion.map(AppUpdatePhase.available) ?? .idle
    }
    mutating func skip() {
        cancelled = true
        availableVersion = nil
        phase = .idle
    }
    mutating func fail() { guard !receivedNoUpdate, !cancelled else { return }; phase = .failed }
    mutating func finish(hasError: Bool) {
        if hasError { fail(); return }
        switch phase {
        case .checking, .downloading, .verifying:
            phase = availableVersion.map(AppUpdatePhase.available) ?? .idle
        default: break
        }
    }
}

struct UpdateConfiguration {
    static let feed = "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/latest/download/appcast.xml"
    static let releases = URL(string: "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases")!
    static let bundleIdentifier = "com.aniketbudhwani.budsbar"

    enum InvalidConfiguration: Error, Equatable { case wrongBundle, invalidFeed, missingPublicKey, unsafePolicy }

    static func validate(_ info: [String: Any]) throws {
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else { throw InvalidConfiguration.wrongBundle }
        guard info["SUFeedURL"] as? String == feed else { throw InvalidConfiguration.invalidFeed }
        guard let encoded = info["SUPublicEDKey"] as? String,
              let key = Data(base64Encoded: encoded), key.count == 32,
              key.contains(where: { $0 != 0 }) else { throw InvalidConfiguration.missingPublicKey }
        guard info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SUSignedFeedFailureExpirationInterval"] as? Int == 0,
              info["SUAllowsAutomaticUpdates"] as? Bool == false,
              info["SUAutomaticallyUpdate"] as? Bool == false else { throw InvalidConfiguration.unsafePolicy }
    }

    static func effectiveFeed(_ info: [String: Any], allowTestFeed: Bool = false) -> String {
        guard allowTestFeed, info["BudsBarUpdateTestBuild"] as? Bool == true,
              let candidate = info["BudsBarTestFeedURL"] as? String,
              let url = URL(string: candidate), url.scheme == "http",
              ["localhost", "127.0.0.1", "[::1]"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path == "/appcast.xml", url.port != nil else { return feed }
        return candidate
    }

    static func versionLabel(_ info: [String: Any]) -> String {
        guard let version = info["CFBundleShortVersionString"] as? String, !version.isEmpty else { return "版本未知" }
        return "v\(version)"
    }
}
