import Foundation
import Observation
import ServiceManagement

@Observable
final class AppSettings {
    private enum Key {
        static let preferredDeviceAddress = "preferredDeviceAddress"
        static let lowBatteryNotificationsEnabled = "lowBatteryNotificationsEnabled"
        static let connectHUDEnabled = "connectHUDEnabled"
        static let reconnectHUDEnabled = "reconnectHUDEnabled"
        static let unexpectedDisconnectHUDEnabled = "unexpectedDisconnectHUDEnabled"
        static let menuBarBatteryEnabled = "menuBarBatteryEnabled"
        static let dockIconEnabled = "dockIconEnabled"
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"
    }

    private let defaults: UserDefaults
    private(set) var launchesAtLogin: Bool
    private(set) var lowBatteryNotificationsEnabled: Bool
    private(set) var connectHUDEnabled: Bool
    private(set) var reconnectHUDEnabled: Bool
    private(set) var unexpectedDisconnectHUDEnabled: Bool
    private(set) var menuBarBatteryEnabled: Bool
    private(set) var dockIconEnabled: Bool
    var preferredDeviceAddress: String? {
        didSet {
            if let preferredDeviceAddress {
                defaults.set(preferredDeviceAddress, forKey: Key.preferredDeviceAddress)
            } else {
                defaults.removeObject(forKey: Key.preferredDeviceAddress)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.launchesAtLogin = SMAppService.mainApp.status == .enabled
        self.lowBatteryNotificationsEnabled = defaults.bool(
            forKey: Key.lowBatteryNotificationsEnabled)
        self.connectHUDEnabled = Self.bool(
            defaults, key: Key.connectHUDEnabled, defaultValue: true)
        self.reconnectHUDEnabled = Self.bool(
            defaults, key: Key.reconnectHUDEnabled, defaultValue: true)
        self.unexpectedDisconnectHUDEnabled = Self.bool(
            defaults, key: Key.unexpectedDisconnectHUDEnabled, defaultValue: true)
        self.menuBarBatteryEnabled = defaults.bool(forKey: Key.menuBarBatteryEnabled)
        self.dockIconEnabled = Self.bool(
            defaults, key: Key.dockIconEnabled, defaultValue: true)
        self.preferredDeviceAddress = defaults.string(forKey: Key.preferredDeviceAddress)
    }

    func refreshLaunchAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()
            if enabled && !launchesAtLogin {
                return "请在系统设置 > 通用 > 登录项中允许耳机控制启动。"
            }
            return nil
        } catch {
            refreshLaunchAtLogin()
            return "开机自动启动设置失败：\(error.localizedDescription)"
        }
    }

    func setLowBatteryNotificationsEnabled(_ enabled: Bool) {
        lowBatteryNotificationsEnabled = enabled
        defaults.set(enabled, forKey: Key.lowBatteryNotificationsEnabled)
    }

    func setConnectHUDEnabled(_ enabled: Bool) {
        connectHUDEnabled = enabled
        defaults.set(enabled, forKey: Key.connectHUDEnabled)
    }

    func setReconnectHUDEnabled(_ enabled: Bool) {
        reconnectHUDEnabled = enabled
        defaults.set(enabled, forKey: Key.reconnectHUDEnabled)
    }

    func setUnexpectedDisconnectHUDEnabled(_ enabled: Bool) {
        unexpectedDisconnectHUDEnabled = enabled
        defaults.set(enabled, forKey: Key.unexpectedDisconnectHUDEnabled)
    }

    func setMenuBarBatteryEnabled(_ enabled: Bool) {
        menuBarBatteryEnabled = enabled
        defaults.set(enabled, forKey: Key.menuBarBatteryEnabled)
    }

    func setDockIconEnabled(_ enabled: Bool) {
        dockIconEnabled = enabled
        defaults.set(enabled, forKey: Key.dockIconEnabled)
    }

    func hasSeenWhatsNew(version: String) -> Bool {
        defaults.string(forKey: Key.lastSeenWhatsNewVersion) == version
    }

    func markWhatsNewSeen(version: String) {
        defaults.set(version, forKey: Key.lastSeenWhatsNewVersion)
    }

    private static func bool(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }
}

enum AppVisibilityPolicy {
    static func shouldShowMenuBarItem(
        isDeviceAvailable: Bool,
        dockIconEnabled: Bool
    ) -> Bool {
        isDeviceAvailable || !dockIconEnabled
    }
}
