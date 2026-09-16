import AppKit
import BudsCore
import SwiftUI

/// Draws the compact two-line battery text independently of `NSStatusBarButtonCell`.
///
/// A status button's cell is designed for one-line menu bar titles. Giving that cell a
/// newline makes its offscreen and real-menu-bar layouts disagree, which can push the
/// second line outside the button. This view owns the full button height and centres two
/// explicit line boxes, so AppKit has no multiline button title to reinterpret.
final class MenuBarBatteryLabel: NSView {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    static let lineHeight = ceil(font.ascender - font.descender + font.leading)

    var text = "" {
        didSet {
            guard text != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep the entire status item clickable, including directly over the readout.
        nil
    }

    var preferredWidth: CGFloat {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(2)
            .map { ceil((String($0) as NSString).size(withAttributes: textAttributes).width) }
            .max() ?? 0
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(2)
        guard !lines.isEmpty else { return }

        let totalHeight = Self.lineHeight * CGFloat(lines.count)
        // Font ascender/descender metrics centre the line boxes, but this all-uppercase and
        // numeric content has more visible ink on one side of the baseline. A one-point
        // optical correction centres the pixels users actually see, not the invisible space.
        let top = floor((bounds.height - totalHeight) / 2) - 1
        for (index, line) in lines.enumerated() {
            let rect = NSRect(
                x: 0,
                y: top + CGFloat(index) * Self.lineHeight,
                width: bounds.width,
                height: Self.lineHeight)
            NSAttributedString(string: String(line), attributes: textAttributes).draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor,
        ]
    }
}

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
    private var wakeObserver: NSObjectProtocol?
    private var stabilizingAfterWakeUntil = Date.distantPast
    private var appliedDockIconEnabled: Bool?
    private lazy var quickControlMenu = QuickControlMenu(buds: buds)
    private lazy var globalHotKeyController = GlobalHotKeyController()
    private lazy var quickActionHUD = QuickActionHUDController()
    private let menuBarIconView = NSImageView()
    private let menuBarBatteryLabel = MenuBarBatteryLabel()
    private var localMouseMonitor: Any?
    private lazy var whatsNewPanelController = WhatsNewPanelController()
    private lazy var customEqualizerPanelController = CustomEqualizerPanelController(buds: buds)
    private lazy var hudCoordinator = ConnectionHUDCoordinator(
        snapshot: { [buds] event in
            return HUDSnapshot(buds: buds, event: event)
        },
        isEnabled: { [buds] event in
            switch event {
            case .connected: return buds.connectHUDEnabled
            case .reconnected: return buds.reconnectHUDEnabled
            case .unexpectedDisconnected: return buds.unexpectedDisconnectHUDEnabled
            }
        },
        // Both HUDs anchor to the same corner, so the connection card queues instead of
        // drawing over a quick action that is already on screen.
        isSlotBusy: { [weak self] in self?.quickHUDSlotBusy ?? false })
    /// Mirrors `QuickActionHUDController.onVisibilityChange` for `isSlotBusy`.
    private var quickHUDSlotBusy = false

    /// How long unavailability must persist before the item is removed. The link genuinely
    /// bounces during a quick off→on — the old session's teardown notifications land after
    /// the new link is up and knock it down for a second or two before it recovers — and the
    /// item must ride that out rather than flicker away. A case being shut does not recover,
    /// so the item still disappears, just this much later.
    private static let hideDelay: TimeInterval = 6

    func applicationWillFinishLaunching(_ notification: Notification) {
        syncDockIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        buds.shutdown()
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
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
        let hostingController = NSHostingController(rootView: PanelView(buds: buds))
        hostingController.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        popover.contentViewController = hostingController

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.title = ""
            button.image = nil
            menuBarIconView.imageScaling = .scaleProportionallyDown
            menuBarIconView.contentTintColor = .labelColor
            menuBarIconView.autoresizingMask = []
            menuBarIconView.setAccessibilityElement(false)
            menuBarBatteryLabel.autoresizingMask = []
            button.addSubview(menuBarIconView)
            button.addSubview(menuBarBatteryLabel)
        }
        globalHotKeyController.onPress = { [weak self] in self?.buds.quickToggle() }
        buds.onQuickHotKeyChange = { [weak self] definition in
            self?.globalHotKeyController.replace(with: definition) ?? false
        }
        if let definition = buds.quickNoiseHotKey {
            _ = globalHotKeyController.replace(with: definition)
        }
        buds.onQuickActionFeedback = { [weak self] feedback in
            self?.quickActionHUD.show(feedback)
        }
        // The quick HUD and the connection HUD share one screen slot. A user-triggered
        // action wins it; a connection event that arrives meanwhile is queued, not lost.
        quickActionHUD.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.quickHUDSlotBusy = visible
            if visible {
                self.hudCoordinator.yieldSlot()
            } else {
                self.hudCoordinator.retryDeferredPresentation()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, let button = self.statusItem?.button,
                  event.window === button.window,
                  button.convert(event.locationInWindow, from: nil).x >= 0,
                  button.convert(event.locationInWindow, from: nil).x <= button.bounds.width
            else { return event }
            self.showQuickMenu()
            return nil
        }

        hudCoordinator.observe(connectionObservation)
        buds.onStateChange = { [weak self] in
            guard let self else { return }
            self.syncDockIcon()
            self.syncStatusItem()
            if Date() < self.stabilizingAfterWakeUntil {
                self.hudCoordinator.stabilize(with: self.connectionObservation)
            } else {
                self.hudCoordinator.observe(self.connectionObservation)
            }
        }
        buds.onWhatsNewRequested = { [weak self] in
            self?.whatsNewPanelController.show()
        }
        buds.onCustomEqualizerRequested = { [weak self] in
            guard let self else { return }
            self.popover.performClose(nil)
            self.customEqualizerPanelController.show()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.stabilizingAfterWakeUntil = Date().addingTimeInterval(1)
            // `systemUptime` stops while the Mac sleeps, so a press from before the sleep
            // would otherwise still look fresh. Nothing armed before a wake should fire.
            self.buds.cancelQuickIntent()
            self.hudCoordinator.stabilize(with: self.connectionObservation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                self.buds.refreshConnectionState()
                self.hudCoordinator.stabilize(with: self.connectionObservation)
            }
        }
        syncDockIcon()
        syncStatusItem()
    }

    private func syncDockIcon() {
        let enabled = buds.dockIconEnabled
        guard appliedDockIconEnabled != enabled else { return }
        appliedDockIconEnabled = enabled
        NSApplication.shared.setActivationPolicy(enabled ? .regular : .accessory)
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

        let shouldShow = AppVisibilityPolicy.shouldShowMenuBarItem(
            isDeviceAvailable: buds.isAvailable,
            dockIconEnabled: buds.dockIconEnabled)

        if shouldShow {
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
            menuBarIconView.image = menuBarIcon
        }
        guard statusItem.isVisible, let button = statusItem.button else { return }
        let battery = buds.menuBarBatteryEnabled ? buds.menuBarBatteryPresentation : nil
        layoutStatusItem(button: button, batteryText: battery?.text)
        button.alphaValue = statusItemOpacity
        button.toolTip = statusItemTooltip
    }

    private func layoutStatusItem(button: NSStatusBarButton, batteryText: String?) {
        let text = batteryText ?? ""
        menuBarBatteryLabel.text = text
        menuBarBatteryLabel.isHidden = text.isEmpty

        let iconSize: CGFloat = 18
        let outerPadding: CGFloat = 4
        let textGap: CGFloat = 3
        let textWidth = menuBarBatteryLabel.preferredWidth
        statusItem.length = text.isEmpty
            ? NSStatusItem.squareLength
            : outerPadding + iconSize + textGap + textWidth + outerPadding

        // Setting the item length updates the button bounds synchronously. Both child views
        // occupy that real height; the label performs its own two-line vertical centring.
        let height = button.bounds.height
        let iconX = text.isEmpty ? floor((button.bounds.width - iconSize) / 2) : outerPadding
        menuBarIconView.frame = NSRect(
            x: iconX,
            y: floor((height - iconSize) / 2),
            width: iconSize,
            height: iconSize)
        menuBarBatteryLabel.frame = NSRect(
            x: outerPadding + iconSize + textGap,
            y: 0,
            width: textWidth,
            height: height)
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            buds.quickToggle()
            return
        }
        // macOS treats Control-click as a secondary click; so does the rest of the app.
        if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showQuickMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // The panel is rebuilt from live state each time it opens rather than showing
        // whatever it last rendered.
        buds.refreshConnectionState()
        buds.panelWillOpen()
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

    private func showQuickMenu() {
        guard let button = statusItem?.button else { return }
        popover.performClose(nil)
        quickControlMenu.makeMenu().popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button)
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

    private var connectionObservation: ConnectionExperienceObservation {
        ConnectionExperienceObservation(
            isConnected: buds.isConnected,
            suppressUnexpectedDisconnect: buds.suppressesUnexpectedDisconnectPresentation)
    }

    private var statusItemOpacity: CGFloat {
        if buds.isBusy { return 0.72 }
        return buds.isConnected ? 1 : 0.52
    }

    private var statusItemTooltip: String {
        let state: String
        if buds.isBusy {
            state = buds.isConnected ? "正在断开" : "正在连接"
        } else {
            state = buds.isConnected ? "已连接" : "未连接"
        }
        var parts = [buds.name, state]
        if let battery = buds.menuBarBatteryPresentation.tooltip {
            // The same projection that draws the title, so the two can never disagree. The
            // panel's vendor-then-system fallback is deliberately not used here: naming a bud
            // from a merged system reading is exactly what the menu bar must not do.
            parts.append(battery)
        }
        return parts.joined(separator: " · ")
    }
}
