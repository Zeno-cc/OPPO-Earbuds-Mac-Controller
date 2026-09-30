import Foundation
import Testing
@testable import BudsCore
@testable import BudsBar

@Suite struct DeviceInformationRefreshTests {
    private final class Transport: ControlTransport {
        var eventHandler: ((ControlTransportEvent) -> Void)?
        var isOpen = false
        var sent: [[UInt8]] = []
        var sendSucceeds = true
        func open() { isOpen = true; eventHandler?(.opened) }
        func close() { isOpen = false; eventHandler?(.closed) }
        func send(_ bytes: [UInt8]) -> Bool {
            guard isOpen, sendSucceeds else { return false }
            sent.append(bytes)
            return true
        }
        func receive(_ bytes: [UInt8]) { eventHandler?(.bytes(bytes)) }
    }

    private final class Harness {
        let clock = TestClock()
        let transport = Transport()
        let session: EarbudsSession
        static let information = DeviceInformation(
            modelIdentifier: DeviceInformationField("OPPO Enco Air5 Pro", source: .profileMetadata),
            firmwareVersion: DeviceInformationField("158.158.105", source: .remoteQuery))

        init(cached: Bool = true) {
            var state = EarbudsState()
            if cached { state.deviceInformationFeature = .ready(Self.information) }
            session = EarbudsSession(profile: .encoAir5Pro, transport: transport,
                initialState: state, now: { [clock] in clock.now }, scheduler: clock.schedule)
            session.open()
        }

        func start() -> Bool {
            let accepted = session.retryDeviceInformationSync()
            // Existing initial battery query precedes the information query.
            transport.receive([0xaa,0x0d,0,0,6,0x81,2,6,0,0,2,1,100,2,100])
            clock.advance(by: 0.2)
            return accepted
        }

        func reply(valid: Bool = true, sequence: UInt8? = nil) {
            let payload = valid
                ? [UInt8(0),4] + Array("1,2,158,2,2,158,3,1,01,3,2,105".utf8)
                : [0,4]
            transport.receive(BudsProtocol.makeFrame(0,0,5,0x81,
                sequence: sequence ?? transport.sent.last![6], payload: payload))
        }
    }

    @Test func unchangedCachedValueStillCompletesRefresh() {
        let h = Harness()
        #expect(h.start())
        #expect(h.session.state.deviceInformationRefresh == .loading)
        #expect(h.session.state.deviceInformationFeature == .ready(Harness.information))
        h.reply()
        #expect(h.session.state.deviceInformationRefresh == .succeeded)
        #expect(h.session.state.deviceInformationFeature == .ready(Harness.information))
    }

    @Test func cachedTimeoutIsVisibleWithoutDiscardingInformation() {
        let h = Harness()
        #expect(h.start())
        h.clock.advance(by: 2.5)
        #expect(h.session.state.deviceInformationRefresh == .failed("读取设备信息失败"))
        #expect(h.session.state.deviceInformationFeature == .ready(Harness.information))
    }

    @Test func cachedMalformedResponseIsVisible() {
        let h = Harness()
        #expect(h.start())
        h.reply(valid: false)
        #expect(h.session.state.deviceInformationRefresh == .failed("设备信息响应格式异常"))
        #expect(h.session.state.deviceInformationFeature == .ready(Harness.information))
    }

    @Test func repeatedRefreshDoesNotCreateAnotherQueryOrResult() {
        let h = Harness()
        #expect(h.start())
        let packets = h.transport.sent.count
        #expect(!h.session.retryDeviceInformationSync())
        #expect(h.transport.sent.count == packets)
        h.reply()
        h.clock.advance(by: 3)
        #expect(h.transport.sent.filter { Array($0[4...5]) == [5,1] }.count == 1)
        #expect(h.session.state.deviceInformationRefresh == .succeeded)
    }

    @Test func cancellationEndsLoadingAndLateReplyCannotBecomeSuccess() {
        let h = Harness()
        #expect(h.start())
        let oldSequence = h.transport.sent.last![6]
        h.session.close()
        #expect(h.session.state.deviceInformationRefresh == .cancelled)
        #expect(h.session.state.deviceInformationFeature == .ready(Harness.information))
        h.reply(sequence: oldSequence)
        h.session.open()
        h.reply(sequence: oldSequence)
        #expect(h.session.state.deviceInformationRefresh != .succeeded)
    }

    @Test func cancellationWithoutCacheDoesNotLeaveLoadingData() {
        let h = Harness(cached: false)
        #expect(h.start())
        h.session.close()
        #expect(h.session.state.deviceInformationRefresh == .cancelled)
        #expect(h.session.state.deviceInformationFeature == .unknown)
    }

    @Test func retryAfterFailureCanSucceed() {
        let h = Harness()
        #expect(h.start())
        h.reply(valid: false)
        h.clock.advance(by: 5)
        #expect(h.session.retryDeviceInformationSync())
        #expect(h.session.state.deviceInformationRefresh == .loading)
        h.reply()
        #expect(h.session.state.deviceInformationRefresh == .succeeded)
    }

    @Test @MainActor func budsProjectsRealOutcomeAndRejectsBusyRefresh() {
        let h = Harness()
        let buds = Buds(session: h.session, now: { h.clock.now }, scheduleTimeout: { _,_ in })
        #expect(h.start())
        #expect(buds.deviceInformationRefresh == .loading)
        #expect(!buds.refreshDeviceInformation())
        h.reply(valid: false)
        #expect(buds.deviceInformationRefresh == .failed("设备信息响应格式异常"))
        #expect(buds.deviceInformationFeature == .ready(Harness.information))
    }
}
