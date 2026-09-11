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

    /// Exposed for tests: the panel must never be shorter than the copy it holds.
    var contentSize: NSSize { panel.contentView?.frame.size ?? panel.frame.size }

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: WhatsNewView.contentWidth + 40, height: 480),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: true)
        self.panel = panel

        panel.title = "v1.5 新功能"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: WhatsNewView {
            panel.close()
        })
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        // The height follows the copy, so a future release that adds a feature grows the
        // panel instead of clipping the last row.
        panel.setContentSize(hosting.view.fittingSize)
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
