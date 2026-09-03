import BudsCore
import Foundation
import IOBluetooth
import Observation

/// Live state of the earbuds plus the Bluetooth plumbing that produces it.
///
/// Two independent links are involved:
///   - the baseband connection (`openConnection`/`closeConnection`), which is what the
///     power toggle in the UI drives, and
///   - the vendor RFCOMM control channel (`oppointeraction`), which carries noise-control
///     and per-bud battery. The latter only exists while the former is up.
@Observable
final class Buds: NSObject {

    /// Raw protocol logging, off unless asked for — the buds push status every few seconds.
    static let isTracing = ProcessInfo.processInfo.environment["BUDSBAR_TRACE"] != nil

    // MARK: - Published state

    static let fallbackName = "耳机"

    var name: String = Buds.fallbackName
    /// Guards the one-shot background lookup in `syncName`; cleared on a new link.
    private var hasReadDisplayName = false
    var isConnected = false
    /// True once the vendor control channel is open — noise control needs it.
    var isControlChannelOpen = false
    var battery = Battery()
    /// Battery values exposed by macOS's Bluetooth runtime. This is a fallback while the
    /// vendor channel has not reported a per-bud value; macOS may expose only one aggregate
    /// headset percentage on the audio link.
    var systemBattery = Battery()
    var placement = Placement()
    var mode: NoiseMode?
    /// How hard noise cancellation is working. nil before the first report or when the
    /// earbuds send a value this profile does not know.
    var ancLevel: ANCLevel?
    /// Set while a connect/disconnect is in flight so the toggle can't be double-fired.
    var isBusy = false
    var lastError: String?
    private let settings = AppSettings()
    var launchesAtLogin: Bool { settings.launchesAtLogin }

    struct DeviceOption: Identifiable, Equatable {
        let id: String
        let name: String
        let isAdapted: Bool
    }

    private(set) var availableDevices: [DeviceOption] = []
    var selectedDeviceAddress: String? { device?.addressString.map(Self.normalizedAddress) }
    var isDeviceSelectionLocked: Bool {
        ProcessInfo.processInfo.environment["BUDSBAR_ADDRESS"] != nil
    }

    /// Set when the power toggle was used to switch the buds off.
    ///
    /// Sticky, and it outranks every other signal — including frames still arriving on the
    /// control channel. A worn earbud re-pages the Mac within a second of `closeConnection`
    /// and macOS brings the audio link straight back up, so anything that reads the link as
    /// evidence of intent ends up undoing the switch-off the user just asked for. Off means
    /// off until the toggle is used again; only `connect()` clears this.
    private(set) var isSwitchedOff = false

    /// Set when a connect the *user* asked for failed, so the item stays on screen with the
    /// error on it. Deliberately not `isSwitchedOff`: that flag also stops the auto-connect
    /// poll, and the user asked for on — the buds are routinely slow to accept the first page
    /// after being dropped, so the retry is exactly what recovers it.
    private var didFailUserConnect = false

    /// Whether the menu bar item should exist at all.
    ///
    /// Classic Bluetooth has no way to ask whether a device is nearby short of paging it,
    /// and paging *is* connecting — `remoteNameRequest` answers from cache, so it cannot
    /// tell a closed case from an open one. So availability is inferred rather than probed:
    /// either the buds are connected, or they were switched off deliberately and the user
    /// needs the toggle to switch them back on. Buds sitting in a shut case are neither, and
    /// the item disappears.
    ///
    /// Busy counts too — but only when the attempt is the user's. Flipping the toggle back
    /// on clears `isSwitchedOff` before the link exists, and without the busy term the item
    /// would vanish the moment it was flipped. The background retry must NOT get the same
    /// courtesy: against a shut case openConnection() blocks for the full page timeout, so
    /// counting auto attempts kept resurfacing the red icon for ~10s of every 20.
    /// With nothing paired the item stays put regardless, so the panel can say why instead
    /// of the app being invisible and looking broken.
    var isAvailable: Bool {
        !isPaired || isConnected || isSwitchedOff || didFailUserConnect
            || (isBusy && !isAutoConnecting)
    }

    /// True while the in-flight connect attempt came from the poll rather than the user.
    private var isAutoConnecting = false

    /// False when no paired device speaks the control protocol — nothing to drive.
    var isPaired: Bool { device != nil }

    /// More than one compatible device exists, but none has been chosen or remembered yet.
    /// The status item remains available so the panel can present the picker.
    var requiresDeviceSelection: Bool {
        device == nil && availableDevices.count > 1 && !isDeviceSelectionLocked
    }

    var supportsNoiseControl: Bool {
        protocolProfile.capabilities.contains(.noiseControl)
    }

    /// Called whenever `isAvailable` or `isConnected` may have moved, so the status item can
    /// insert, remove, or recolour itself. A plain callback rather than observation: the
    /// owner is AppKit, not a SwiftUI view.
    var onStateChange: (() -> Void)?

    typealias Battery = EarbudsBatteryState

    /// Where each bud is, as the buds report it. nil until they have said.
    ///
    /// This is what stops a bud charging in the case from being drawn as one in use. It also
    /// covers a gap in the battery report: a bud in the case drops out of it entirely rather
    /// than reporting as unknown, and an absent slot deliberately keeps its last value — so
    /// without placement the panel showed a frozen percentage for a bud that was put away.
    typealias Placement = EarbudsPlacementState

    // MARK: - Private

    private var device: IOBluetoothDevice?
    /// Selected from the advertised model name. The frame format is shared, but Air5 Pro's
    /// mode values and reported value width differ from T500 Pro's.
    private var protocolProfile: BudsProtocol.Profile = .unknown
    private var controlTransport: RFCOMMTransport?
    private var earbudsSession: EarbudsSession?
    private var disconnectObserver: IOBluetoothUserNotification?

    /// Until when the link is taken as up on the strength of a positive event, whatever the
    /// `isConnected()` query says. The query lags several seconds behind an openConnection
    /// that has already returned success — the trace showed it still false through three
    /// deviceDidConnect callbacks — and the refresh that trusted it hid the menu bar item in
    /// the gap. Real evidence of a drop (deviceDidDisconnect) cancels the assertion early.
    private var linkAssertedUntil = Date.distantPast

    /// Covers the observed lag with slack; a wrong assertion self-corrects at the next poll.
    private static let linkAssertionGrace: TimeInterval = 10

    /// When a frame last arrived from the buds.
    ///
    /// This is the one unambiguous signal the app has. `isConnected()` under-reports, and
    /// `deviceDidDisconnect` fires on drops the data stream then carries on straight through
    /// — the trace showed battery and mode reports still landing while both the link and the
    /// channel were believed down. Bytes cannot arrive from earbuds that are not there.
    private var lastFrameAt = Date.distantPast

    /// How long the last frame counts for. The buds push status every few seconds unprompted,
    /// so a gap this long means they have genuinely gone rather than merely fallen quiet.
    private static let frameFreshness: TimeInterval = 8

    /// True while frames are arriving often enough to prove the buds are present.
    private var isStreamLive: Bool { Date().timeIntervalSince(lastFrameAt) < Self.frameFreshness }

    private func assertLinkUp() {
        isConnected = true
        didFailUserConnect = false
        linkAssertedUntil = Date().addingTimeInterval(Self.linkAssertionGrace)
    }
    private var pollTimer: Timer?
    private var ticks = 0
    /// Aggregate value read through macOS's accessory-power service. Kept separate so the
    /// two-second IOBluetooth poll cannot erase it with the same stale empty wrapper that
    /// made the fallback necessary.
    private var accessoryBattery: Int?
    private var isAccessoryBatteryRequestInFlight = false
    private var lastAccessoryBatteryRequestAt = Date.distantPast

    override init() {
        super.init()
        refreshPairedDevices()
        device = selectedDeviceCandidate()
        protocolProfile = BudsProtocol.Profile.forDeviceName(device?.name)
        syncName()

        // Fires for *any* device connecting; we filter to ours. There is no
        // per-device connect notification in IOBluetooth, only a global one.
        IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:)))

        refreshConnectionState()

        // Two jobs at two rates. Re-reading the link is a local query, so it runs often and
        // keeps `isConnected` honest no matter which notification was missed. Actually
        // reaching for the buds pages the radio, so that only happens every tenth tick.
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshConnectionState()
            self.ticks += 1
            if self.ticks % Self.ticksPerConnectAttempt == 0 { self.attemptAutoConnect() }
        }
        pollTimer?.tolerance = Self.pollInterval / 2   // no deadline worth a forced wakeup
        attemptAutoConnect()
    }

    // MARK: - Launch at login

    /// Refreshes the value in case the user changed the login-item permission in System
    /// Settings while the panel was closed.
    func refreshLaunchAtLoginState() {
        settings.refreshLaunchAtLogin()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        lastError = settings.setLaunchAtLogin(enabled)
    }

    /// How often the link state is re-read. `isConnected()` is a local lookup, not a radio
    /// round trip, so this can be brisk — it sets how fast the menu bar item reacts to a
    /// case being shut.
    private static let pollInterval: TimeInterval = 2

    /// Connect attempts are the expensive part — a shut case answers with a page timeout —
    /// so they run every tenth poll, i.e. every 20s.
    /// ponytail: fixed interval, not a backoff. Tune these two before adding one.
    private static let ticksPerConnectAttempt = 10

    private func attemptAutoConnect() {
        // Pairing can happen while we are running, so keep looking until something turns up.
        refreshPairedDevices()
        if device == nil {
            device = selectedDeviceCandidate()
            protocolProfile = BudsProtocol.Profile.forDeviceName(device?.name)
            if device != nil { hasReadDisplayName = false }
        }
        guard !isConnected, !isSwitchedOff, !isBusy else { return }
        connect(auto: true)
    }

    /// Picks the paired device that advertises the `oppointeraction` control service.
    ///
    /// Matching on the service rather than on a hardcoded address means any earbuds
    /// speaking this protocol work, and no one's Bluetooth address ends up in the source.
    /// `BUDSBAR_ADDRESS` forces a specific one when several are paired.
    private func selectedDeviceCandidate() -> IOBluetoothDevice? {
        BluetoothDeviceDiscovery.select(
            forcedAddress: ProcessInfo.processInfo.environment["BUDSBAR_ADDRESS"],
            preferredAddress: settings.preferredDeviceAddress)
    }

    func selectDevice(address: String) {
        guard !isDeviceSelectionLocked, !isBusy else { return }
        let wanted = Self.normalizedAddress(address)
        guard wanted != selectedDeviceAddress,
              let next = BluetoothDeviceDiscovery.pairedOPODevices().first(where: {
                  Self.normalizedAddress($0.addressString ?? "") == wanted
              })
        else { return }

        closeControlChannel()
        disconnectObserver?.unregister()
        disconnectObserver = nil
        device = next
        settings.preferredDeviceAddress = wanted
        protocolProfile = BudsProtocol.Profile.forDeviceName(next.name)
        name = next.name ?? Self.fallbackName
        hasReadDisplayName = false
        isConnected = false
        isSwitchedOff = false
        didFailUserConnect = false
        linkAssertedUntil = .distantPast
        lastFrameAt = .distantPast
        battery = Battery()
        systemBattery = Battery()
        accessoryBattery = nil
        lastAccessoryBatteryRequestAt = .distantPast
        placement = Placement()
        mode = nil
        ancLevel = nil
        refreshConnectionState()
    }

    private func refreshPairedDevices() {
        availableDevices = BluetoothDeviceDiscovery.pairedOPODevices().compactMap { device in
            guard let address = device.addressString else { return nil }
            let profile = BudsProtocol.Profile.forDeviceName(device.name)
            return DeviceOption(
                id: Self.normalizedAddress(address),
                name: device.name ?? Self.fallbackName,
                isAdapted: profile != .unknown)
        }
    }

    private static func normalizedAddress(_ value: String) -> String {
        DeviceSelectionPolicy.normalizedAddress(value)
    }

    /// Called at app termination. Releasing the RFCOMM channel matters: macOS grants one
    /// per device, and a channel left to the OS reaper can refuse the next launch its open.
    func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        testTimer?.invalidate()
        testTimer = nil
        disconnectObserver?.unregister()
        disconnectObserver = nil
        closeControlChannel()
    }

    // MARK: - Power toggle

    func connect(auto: Bool = false) {
        guard !isBusy, let device else { return }
        isAutoConnecting = auto
        // Intent is cleared straight away — the user asked for on, so the auto-connect poll
        // must be free to keep retrying. What holds the menu bar item in place across the
        // attempt is `isBusy` being part of `isAvailable`, not this flag.
        isSwitchedOff = false
        isBusy = true
        // Background retries neither surface errors nor erase one the user is reading.
        if !auto { lastError = nil }
        onStateChange?()
        // openConnection blocks until the baseband link is up or times out.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = device.openConnection()
            DispatchQueue.main.async {
                self.isBusy = false
                self.isAutoConnecting = false
                if result == kIOReturnSuccess { self.assertLinkUp() }
                // A failed background attempt is the normal state of a shut case, not an
                // error to display when the item next appears. A failed USER attempt is
                // different: with `isSwitchedOff` already cleared and `isBusy` ending here,
                // every availability term would be false and the item would vanish out from
                // under the toggle the user just flipped. `didFailUserConnect` keeps the item
                // and shows the error while leaving the poll free to retry — parking it in
                // `isSwitchedOff` instead also switched the retry off, so one slow page left
                // the app stuck disconnected until the toggle was used again.
                if result != kIOReturnSuccess, !auto {
                    self.lastError = Self.describe(result)
                    self.didFailUserConnect = true
                }
                // Refresh on both outcomes: a failed attempt still ends `isBusy`, and the
                // status item has to be told, or it sits stale until the next poll.
                self.refreshConnectionState()
            }
        }
    }

    func disconnect() {
        guard !isBusy, let device else { return }
        // The user asked for down — an earlier up-assertion must not outvote them while
        // closeConnection completes.
        linkAssertedUntil = .distantPast
        // Keeps the menu bar item present so the toggle can be switched back on, and stops
        // the auto-connect poll from undoing this a few seconds later.
        isSwitchedOff = true
        // Whatever arrived before this moment no longer counts as evidence of a live link.
        lastFrameAt = .distantPast
        didFailUserConnect = false
        onStateChange?()
        isBusy = true
        closeControlChannel(intent: .disconnectedByUser)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = device.closeConnection()
            DispatchQueue.main.async {
                self.isBusy = false
                if result != kIOReturnSuccess { self.lastError = Self.describe(result) }
                self.refreshConnectionState()
            }
        }
    }

    // MARK: - Connection tracking

    /// The one place the disconnect observer is written. Both `deviceDidConnect` and
    /// `refreshConnectionState` need to register it, and assigning over a live registration
    /// leaks it still armed — a later disconnect then fires every orphaned observer too.
    private func armDisconnectObserver(for device: IOBluetoothDevice) {
        disconnectObserver?.unregister()
        disconnectObserver = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDidDisconnect(_:device:)))
    }

    @objc private func deviceDidConnect(_ notification: IOBluetoothUserNotification, device connected: IOBluetoothDevice) {
        guard connected.addressString == device?.addressString else { return }
        // Re-register per connection; the disconnect notification is one-shot.
        armDisconnectObserver(for: connected)
        DispatchQueue.main.async {
            // A link coming back after a switch-off is macOS re-establishing audio for an
            // earbud that is still being worn, not the user asking for the buds back. It is
            // not evidence of intent, so it does not clear `isSwitchedOff` — nor is there any
            // point asserting a link the app has been told to ignore.
            guard !self.isSwitchedOff else { return }
            self.assertLinkUp()
            // Re-read the display name: a new link is the natural moment to notice a rename.
            self.hasReadDisplayName = false
            self.refreshConnectionState()
        }
    }

    @objc private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification, device disconnected: IOBluetoothDevice) {
        // Fired means spent — it is one-shot — so nil without unregister is correct here.
        disconnectObserver = nil
        DispatchQueue.main.async {
            self.linkAssertedUntil = .distantPast   // a real drop beats any grace window
            self.closeControlChannel()
            self.refreshConnectionState()
        }
    }

    /// Mirrors the name macOS shows in the Bluetooth settings.
    ///
    /// That is not `IOBluetoothDevice.name`, which reports the name the earbuds advertise
    /// over the air — renaming a device in Bluetooth settings does not change what the
    /// hardware calls itself, so the two drift apart (here: "Realme Buds" on screen,
    /// "realme Buds T500 Pro" over the air). Only the Bluetooth daemon holds the display
    /// name; it is in no readable preference file or IORegistry entry, and
    /// `system_profiler` is the one interface that reports it.
    ///
    /// Spawning a process is far too slow for the 2s poll that calls this, so the lookup
    /// runs once in the background and is repeated only when a new link comes up — which
    /// is also when a rename would realistically be noticed. The advertised name stands in
    /// meanwhile, and the hardcoded default only shows before either has answered.
    private func syncName() {
        if name == Self.fallbackName, let advertised = device?.name, !advertised.isEmpty {
            name = advertised
        }

        guard !hasReadDisplayName else { return }
        hasReadDisplayName = true
        guard let address = device?.addressString else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let displayName = Self.displayNameFromSystemProfiler(address: address)
            else { return }
            DispatchQueue.main.async {
                if self.name != displayName {
                    self.name = displayName
                    self.onStateChange?()
                }
            }
        }
    }

    /// Reads the name Bluetooth settings shows. Each device is a single-pair dictionary
    /// keyed by its display name, so the key is the value we want and the address inside
    /// identifies which entry is ours.
    private static func displayNameFromSystemProfiler(address: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // Drain before waiting: a full pipe buffer would deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }

        let wanted = address.replacingOccurrences(of: "-", with: ":").uppercased()
        for section in sections {
            // Look in both lists so the name is right even when the buds are away.
            for listKey in ["device_connected", "device_not_connected"] {
                guard let list = section[listKey] as? [[String: Any]] else { continue }
                for entry in list {
                    for (displayName, raw) in entry {
                        guard let info = raw as? [String: Any],
                              let addr = info["device_address"] as? String,
                              addr.uppercased() == wanted
                        else { continue }
                        return displayName
                    }
                }
            }
        }
        return nil
    }

    func refreshConnectionState() {
        syncName()
        // A live stream outranks everything else. `isConnected()` under-reports badly — it
        // goes false while the headset link is plainly still up, because the audio side holds
        // its own reference to a device this process has stopped connecting to — and the
        // assertion grace only papered over that for its ten seconds. Once it lapsed the
        // toggle flipped itself off, auto-connect asserted the link up again, and the two took
        // turns forever. The remaining terms are for the window before the first frame lands.
        //
        // A switch-off beats all of it. Frames keep arriving for a while after
        // `closeConnection` — believing them would put the app straight back into the loop
        // under a new name.
        let connected = !isSwitchedOff
            && (isStreamLive
                || isControlChannelOpen
                || (device?.isConnected() ?? false)
                || Date() < linkAssertedUntil)
        if connected != isConnected {
            AppLogger.bluetooth.debug(
                "Link changed connected=\(connected) stream=\(self.isStreamLive) channel=\(self.isControlChannelOpen) available=\(connected || self.isSwitchedOff)")
        }
        isConnected = connected
        // `isSwitchedOff` is deliberately not touched here. It is user intent, and this
        // method is a state re-read that the poll calls every 2s — clearing the flag on
        // `connected` raced the poll against closeConnection(): the tick landing before the
        // link finished dropping saw connected=true, wiped the just-set flag, and the item
        // vanished once the drop completed. Intent is written only by connect()/disconnect()
        // and by deviceDidConnect (a genuine new link means the buds are on and in use).
        defer { onStateChange?() }
        if connected {
            // The connect notification only fires for connections made while we are running,
            // so buds already connected at launch would never get a disconnect observer —
            // and shutting the case would go unnoticed, leaving the menu bar item on screen.
            if disconnectObserver == nil, let device {
                armDisconnectObserver(for: device)
            }
            refreshSystemBattery()
            openControlChannel()
        } else {
            // The closed case stops sending its battery block and an audio-link handoff can
            // briefly make the RFCOMM link look down. Keep the last confirmed case level for
            // this app run; left/right readings are discarded because they change faster and
            // are immediately re-reported when either bud is active again.
            battery = Battery(left: nil, right: nil, enclosure: battery.enclosure, combined: nil)
            systemBattery = Battery()
            accessoryBattery = nil
            lastAccessoryBatteryRequestAt = .distantPast
            placement = Placement()
            mode = nil
            ancLevel = nil
        }
    }

    // MARK: - System battery

    /// Reads the battery indicators maintained by macOS for Bluetooth audio devices.
    ///
    /// These selectors are present on the macOS IOBluetooth runtime but are not part of
    /// the public SDK headers. `responds(to:)` keeps older/newer runtimes without a given
    /// indicator readable, and KVC safely boxes the Objective-C scalar result as NSNumber.
    private static func systemBatteryValue(_ device: IOBluetoothDevice, key: String) -> Int? {
        let selector = Selector(key)
        guard device.responds(to: selector),
              let number = device.value(forKey: key) as? NSNumber
        else { return nil }

        let value = number.intValue
        return (1...100).contains(value) ? value : nil
    }

    /// Updates the system fallback without overwriting vendor-protocol readings. The two
    /// sources have different lifetimes: a vendor frame can identify a bud's placement,
    /// while the system audio link may only expose one aggregate percentage.
    private func refreshSystemBattery() {
        guard let device, let address = device.addressString else { return }
        // IOBluetooth wrappers can keep stale battery indicators across both a normal
        // reconnect and a Bluetooth power cycle. Always read a current paired-device
        // snapshot; this method already runs on the existing two-second connected poll.
        let source = BluetoothDeviceDiscovery.pairedDeviceSnapshot(address: address) ?? device

        var next = Battery(
            left: Self.systemBatteryValue(source, key: "batteryPercentLeft"),
            right: Self.systemBatteryValue(source, key: "batteryPercentRight"),
            enclosure: Self.systemBatteryValue(source, key: "batteryPercentCase"),
            combined: Self.systemBatteryValue(source, key: "batteryPercentCombined")
                ?? Self.systemBatteryValue(source, key: "batteryPercentSingle")
        )

        let runtimeHasHeadsetBattery = next.left != nil || next.right != nil
            || next.combined != nil
        if runtimeHasHeadsetBattery {
            accessoryBattery = nil
        } else {
            next.combined = accessoryBattery
        }

        if next != systemBattery {
            systemBattery = next
            if Self.isTracing {
                let value = next.combined.map(String.init) ?? "unknown"
                AppLogger.bluetooth.debug("System battery combined=\(value, privacy: .public)")
            }
        }

        let vendorHasHeadsetBattery = battery.left != nil || battery.right != nil
            || battery.combined != nil
        if !runtimeHasHeadsetBattery, !vendorHasHeadsetBattery {
            requestAccessoryBatteryIfNeeded(
                deviceName: device.name ?? name,
                address: Self.normalizedAddress(address))
        }
    }

    /// `pmset` is a subprocess, so it is used only when both normal battery sources are
    /// empty and no more than once per interval. The result is aggregate by definition and
    /// is therefore assigned only to `combined`, never copied into left and right.
    private static let accessoryBatteryRefreshInterval: TimeInterval = 10

    private func requestAccessoryBatteryIfNeeded(deviceName: String, address: String) {
        guard !isAccessoryBatteryRequestInFlight,
              Date().timeIntervalSince(lastAccessoryBatteryRequestAt)
                  >= Self.accessoryBatteryRefreshInterval
        else { return }

        isAccessoryBatteryRequestInFlight = true
        lastAccessoryBatteryRequestAt = Date()
        DispatchQueue.global(qos: .utility).async {
            let value = SystemAccessoryBatteryReader.read(deviceName: deviceName)
            DispatchQueue.main.async {
                self.isAccessoryBatteryRequestInFlight = false
                guard self.isConnected, self.selectedDeviceAddress == address else { return }
                self.accessoryBattery = value
                // Compose the fresh aggregate with any case value immediately; do not make
                // the user wait for the next two-second UI poll.
                self.refreshSystemBattery()
                self.onStateChange?()
            }
        }
    }

    // MARK: - Vendor control channel

    private func openControlChannel() {
        if let earbudsSession {
            switch earbudsSession.connectionState {
            case .idle, .failed:
                earbudsSession.open(intent: isAutoConnecting ? .automatic : .connected)
            default:
                break
            }
            return
        }

        guard let device else { return }
        let transport = RFCOMMTransport(device: device, tracing: Self.isTracing)
        var initialState = EarbudsState()
        initialState.battery = battery
        initialState.placement = placement
        initialState.mode = mode
        initialState.ancLevel = ancLevel
        let session = EarbudsSession(
            profile: protocolProfile, transport: transport, initialState: initialState)
        session.onActivity = { [weak self] in self?.controlChannelBecameActive() }
        session.onStateChange = { [weak self] in self?.syncSessionState() }
        controlTransport = transport
        earbudsSession = session
        session.open(intent: isAutoConnecting ? .automatic : .connected)
    }

    private func closeControlChannel(intent: ConnectionIntent = .automatic) {
        earbudsSession?.close(intent: intent)
        earbudsSession = nil
        controlTransport = nil
        isControlChannelOpen = false
    }

    private func controlChannelBecameActive() {
        guard !isSwitchedOff else {
            closeControlChannel(intent: .disconnectedByUser)
            return
        }
        lastFrameAt = Date()
        assertLinkUp()
    }

    private func syncSessionState() {
        guard let earbudsSession else { return }
        isControlChannelOpen = earbudsSession.connectionState == .ready

        let next = earbudsSession.state
        battery = next.battery
        placement = next.placement
        mode = next.mode
        ancLevel = next.ancLevel

        if case .failed(let error) = earbudsSession.connectionState {
            lastError = error.message
            AppLogger.session.error("Session failed: \(error.message, privacy: .public)")
        } else if isControlChannelOpen {
            lastError = nil
            if ProcessInfo.processInfo.environment["BUDSBAR_TEST"] != nil,
               testTimer == nil, testQueue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.startModeTest() }
            }
        }
        onStateChange?()
    }

    // MARK: - Noise control

    func set(mode requested: NoiseMode) {
        // Deliberately not updating `mode` here. The buds echo a state notification
        // once they have actually switched, and that echo is what the UI renders —
        // it is also what keeps this panel and realme Link on the phone in agreement.
        guard supportsNoiseControl else {
            lastError = "此耳机型号尚未适配降噪控制"
            return
        }
        if earbudsSession?.set(mode: requested, rememberedLevel: ancLevel) != true {
            lastError = "控制通道尚未就绪"
        }
    }

    /// Same contract as `set(mode:)` — the level shown is the level the buds reported, not
    /// the one that was asked for, so the panel and realme Link cannot drift apart.
    func set(ancLevel requested: ANCLevel) {
        guard supportsNoiseControl else {
            lastError = "此耳机型号尚未适配降噪控制"
            return
        }
        if earbudsSession?.set(ancLevel: requested) != true {
            lastError = "控制通道尚未就绪"
        }
    }

    // MARK: - Mode cycle test

    /// Drives every mode and every ANC level in turn so the commands can be verified end to
    /// end against the notifications the buds send back. Runs only under BUDSBAR_TEST=1.
    private var testQueue: [(label: String, send: () -> Void)] = []
    private var testTimer: Timer?

    private func startModeTest() {
        guard isControlChannelOpen else { return }
        testQueue = ANCLevel.allCases.map { level in
            ("ANC \(level.label), value \(self.protocolProfile.wire(for: level).map(String.init) ?? "unsupported")",
             { [weak self] in self?.set(ancLevel: level) })
        } + [
            ("Transparency", { [weak self] in self?.set(mode: .transparency) }),
            ("Off", { [weak self] in self?.set(mode: .off) }),
        ]
        testLog("cycling modes, 3s apart")
        testTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let next = self.testQueue.first else {
                self.testLog("mode cycle complete")
                self.testTimer?.invalidate()
                self.testTimer = nil
                return
            }
            self.testQueue.removeFirst()
            self.testLog("commanding \(next.label)")
            next.send()
        }
    }

    private func testLog(_ message: String) {
        AppLogger.diagnostics.notice("Mode test: \(message, privacy: .public)")
    }

    // MARK: - Errors

    private static func describe(_ code: IOReturn) -> String {
        switch code {
        case kIOReturnSuccess: return "正常"
        case kIOReturnTimeout: return "连接超时——耳机可能处于休眠、充电盒内或超出范围"
        case kIOReturnNoDevice: return "未找到设备"
        case kIOReturnBusy: return "设备忙"
        case kIOReturnExclusiveAccess: return "设备已被其他应用占用"
        case kIOReturnNotOpen: return "设备未打开"
        default: return "系统错误（IOReturn \(code)）"
        }
    }
}
