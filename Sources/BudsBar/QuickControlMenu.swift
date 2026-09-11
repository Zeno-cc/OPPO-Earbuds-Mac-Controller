import AppKit
import BudsCore

final class QuickControlMenu {
    private let buds: Buds

    init(buds: Buds) { self.buds = buds }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // Fails loudly, succeeds quietly: the menu itself already shows the resulting state.
        let toggle = NSMenuItem(title: "切换降噪 / 通透", action: #selector(Buds.quickToggleFromMenu), keyEquivalent: "")
        toggle.target = buds
        toggle.isEnabled = buds.canQuickNoiseControl
        menu.addItem(toggle)
        menu.addItem(.separator())
        for mode in NoiseMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(Buds.chooseNoiseMode(_:)), keyEquivalent: "")
            item.target = buds
            item.representedObject = mode.rawValue
            item.state = buds.mode == mode ? NSControl.StateValue.on : NSControl.StateValue.off
            item.isEnabled = buds.canQuickNoiseControl
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for level in ANCLevel.allCases {
            let item = NSMenuItem(title: "降噪强度：\(level.label)", action: #selector(Buds.chooseANCLevel(_:)), keyEquivalent: "")
            item.target = buds
            item.representedObject = level.rawValue
            item.state = buds.mode == .noiseCancellation && buds.ancLevel == level
                ? NSControl.StateValue.on : NSControl.StateValue.off
            item.isEnabled = buds.canQuickNoiseControl && buds.mode == .noiseCancellation
            menu.addItem(item)
        }
        return menu
    }
}
