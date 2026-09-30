import SwiftUI
import Testing
import BudsCore
@testable import BudsBar

@MainActor @Suite struct PanelPendingLayoutTests {
    private final class Transport: ControlTransport {
        var eventHandler: ((ControlTransportEvent) -> Void)?
        var isOpen = false
        func open() {}
        func close() {}
        func send(_ bytes: [UInt8]) -> Bool { false }
    }

    private func model() -> Buds {
        var state = EarbudsState()
        state.equalizerFeature = .ready(.original)
        state.gameModeFeature = .ready(false)
        let session = EarbudsSession(profile: .encoAir5Pro, transport: Transport(), initialState: state)
        return Buds(session: session, now: { 0 }, scheduleTimeout: { _,_ in })
    }

    @Test func gamePendingKeepsSoundGeometryAndConfirmedValue() {
        let buds = model()
        let host = NSHostingView(rootView: SoundSection(buds: buds).frame(width: 328))
        let ready = host.fittingSize
        buds.pendingGameMode = true
        let pending = host.fittingSize
        #expect(abs(pending.height - ready.height) < 0.5)
        #expect(pending.width == ready.width)
        #expect(buds.gameModeFeature == .ready(false))
    }

    @Test func equalizerPendingDoesNotInsertAnExtraStatusRow() {
        let buds = model()
        let host = NSHostingView(rootView: SoundSection(buds: buds).frame(width: 328))
        let ready = host.fittingSize
        buds.pendingEqualizer = .bass
        let pending = host.fittingSize
        #expect(abs(pending.height - ready.height) < 0.5)
        #expect(pending.width == ready.width)
        #expect(buds.equalizerFeature == .ready(.original))
    }
}
