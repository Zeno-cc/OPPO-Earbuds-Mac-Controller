import AppKit
import BudsCore
import SwiftUI

@main
struct BudsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The app deliberately has no windows. The menu bar item is an NSStatusItem owned by
        // the delegate rather than a MenuBarExtra: `MenuBarExtra(isInserted:)` kept the item
        // on screen with the binding false, and this app's whole point is that it disappears
        // along with the buds. `NSStatusItem.isVisible` does exactly what it says.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private let buds = Buds()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    /// nil until the first sync, so the icon is always drawn once at launch.
    private var lastIconConnected: Bool?
    private var outsideClickMonitor: Any?
    /// Pending hide, so removal can be debounced. See `syncStatusItem`.
    private var hideWorkItem: DispatchWorkItem?

    /// How long unavailability must persist before the item is removed. The link genuinely
    /// bounces during a quick off→on — the old session's teardown notifications land after
    /// the new link is up and knock it down for a second or two before it recovers — and the
    /// item must ride that out rather than flicker away. A case being shut does not recover,
    /// so the item still disappears, just this much later.
    private static let hideDelay: TimeInterval = 6

    func applicationWillTerminate(_ notification: Notification) {
        buds.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        BudsProtocol.selfCheck()
        #endif

        // Not `.transient`: that closes the popover whenever the app resigns active, and
        // connecting or disconnecting the buds shuffles activation enough to trip it — the
        // panel vanished the instant the power toggle was used. Dismissal is handled here
        // instead, by watching for a click outside.
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(buds: buds))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        buds.onStateChange = { [weak self] in self?.syncStatusItem() }
        syncStatusItem()
    }

    /// Adds or removes the item, and keeps its glyph in step. Driven by `Buds`' own poll, so
    /// it runs every couple of seconds — hence the early-outs when nothing actually moved.
    ///
    /// The two checks are deliberately separate. Assigning `isVisible` rebuilds the status
    /// item's window, which dismisses a popover anchored to its button — so switching the
    /// buds off, which changes the icon but not whether the item belongs on screen, must not
    /// go anywhere near it. Writing the same value counts: the setter does the work anyway.
    private func syncStatusItem() {
        // `onStateChange` can in principle fire from Buds' own init work before
        // `applicationDidFinishLaunching` has created the item.
        guard let statusItem else { return }

        if buds.isAvailable {
            // Showing is immediate; any pending hide was a bounce and is void.
            hideWorkItem?.cancel()
            hideWorkItem = nil
            if !statusItem.isVisible {
                statusItem.isVisible = true
                // Re-insertion can rebuild the item's window, so the glyph cannot be
                // trusted to have survived — forget it and let the check below redraw.
                lastIconConnected = nil
            }
        } else if statusItem.isVisible, hideWorkItem == nil {
            // Hiding is debounced: only an outage that outlives the delay is real.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hideWorkItem != nil else { return }
                self.hideWorkItem = nil
                guard !self.buds.isAvailable else { return }
                self.statusItem.isVisible = false
                if self.popover.isShown { self.popover.performClose(nil) }
                self.lastIconConnected = nil
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
        }

        if statusItem.isVisible, lastIconConnected != buds.isConnected {
            lastIconConnected = buds.isConnected
            statusItem.button?.image = menuBarIcon
        }
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // The panel is rebuilt from live state each time it opens rather than showing
        // whatever it last rendered.
        buds.refreshConnectionState()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // Stands in for `.transient`'s click-away dismissal. A global monitor sees only
        // events destined for other apps, so clicks inside the panel — the toggle, the mode
        // buttons — never reach it. Mouse events need no Accessibility grant; key events do.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// The menu bar glyph.
    ///
    /// Disconnected is drawn in red, which means giving up template rendering for that
    /// state: the menu bar recolours a template image to match itself, so a red one would
    /// come out plain monochrome. Connected stays a template so it still follows the menu
    /// bar's own light/dark appearance.
    ///
    /// `airpods.pro.chargingcase.fill` — the name used here before — is not a real symbol,
    /// which is why the disconnected icon was blank. The `.wireless` variant is the one
    /// that exists.
    private var menuBarIcon: NSImage {
        let name = buds.isConnected ? "airpods.pro" : "airpods.pro.chargingcase.wireless.fill"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: name) ?? NSImage()

        guard !buds.isConnected else {
            image.isTemplate = true
            return image
        }
        let red = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemRed])) ?? image
        red.isTemplate = false
        return red
    }
}
