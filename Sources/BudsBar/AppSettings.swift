import Foundation
import Observation
import ServiceManagement

@Observable
final class AppSettings {
    private enum Key {
        static let preferredDeviceAddress = "preferredDeviceAddress"
    }

    private let defaults: UserDefaults
    private(set) var launchesAtLogin: Bool
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
}
