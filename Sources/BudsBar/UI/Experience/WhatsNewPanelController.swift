import AppKit
import SwiftUI

enum WhatsNewPresentationPolicy {
    static func requestIfNeeded(version: String, settings: AppSettings) -> Bool {
        guard !settings.hasSeenWhatsNew(version: version) else { return false }
        settings.markWhatsNewSeen(version: version)
        return true
    }
}

enum WhatsNewPanelPositioning {
    static func centeredOrigin(panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2)
    }
}

final class WhatsNewPanelController {
    private let panel: NSPanel

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 340),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: true)
        self.panel = panel

        panel.title = "v1.3 新功能"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: WhatsNewView {
            panel.close()
        })
    }

    func show() {
        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        centerOnCurrentScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func centerOnCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        else {
            panel.center()
            return
        }

        panel.setFrameOrigin(WhatsNewPanelPositioning.centeredOrigin(
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame))
    }
}
