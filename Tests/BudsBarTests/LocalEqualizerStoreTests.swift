import BudsCore
import XCTest
@testable import BudsBar

final class LocalEqualizerStoreTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "LocalEqualizerStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testRoundTripAndDeletePreserveOtherStableIdentities() throws {
        try withDefaults { defaults in
            let store = LocalEqualizerStore(defaults: defaults)
            let curve = CustomEqualizer.newCurve(name: "听歌").replacingGains([-6,-4,-2,0,2,4,6,1,0,-1])!
            let first = try store.save(curve)
            let second = try store.save(curve)
            XCTAssertNotEqual(first.id, second.id)
            let reopened = LocalEqualizerStore(defaults: defaults)
            XCTAssertEqual(try reopened.load(), [first, second])
            try reopened.delete(id: first.id)
            XCTAssertEqual(try store.load(), [second])
        }
    }

    func testSavedDeviceCurveRestoresAsUnselectedCreationDraft() throws {
        try withDefaults { defaults in
            let bytes: [UInt8] = [0,1,1,250,6,42,1,65,10]
                + CustomEqualizer.bandFrequencies.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8), 2] }
            let device = try XCTUnwrap(CustomEqualizer.decode(bytes))
            let saved = try LocalEqualizerStore(defaults: defaults).save(device)
            let draft = try XCTUnwrap(saved.draft)
            XCTAssertEqual(device.id, 42)
            XCTAssertTrue(device.isSelected)
            XCTAssertEqual(draft.id, 0)
            XCTAssertFalse(draft.isSelected)
            XCTAssertEqual(draft.gains, device.gains)
            XCTAssertEqual(draft.name, device.name)
            XCTAssertNotNil(draft.payload(for: .create))
        }
    }

    func testInvalidPersistedDataCannotBeOverwrittenBySaveOrDelete() throws {
        try withDefaults { defaults in
            let valid = CustomEqualizer.newCurve(name: "有效")
            let store = LocalEqualizerStore(defaults: defaults)
            let id = UUID()
            let invalidJSON = [
                "not json",
                "[{\"id\":\"\(id)\",\"name\":\"A\",\"gains\":[0]}]",
                "[{\"id\":\"\(id)\",\"name\":\"A\",\"gains\":[7,0,0,0,0,0,0,0,0,0]}]",
                "[{\"id\":\"\(id)\",\"name\":\" \",\"gains\":[0,0,0,0,0,0,0,0,0,0]}]"
            ]
            for json in invalidJSON {
                let data = Data(json.utf8)
                defaults.set(data, forKey: LocalEqualizerStore.storageKey)
                XCTAssertThrowsError(try store.load())
                XCTAssertThrowsError(try store.save(valid))
                XCTAssertThrowsError(try store.delete(id: id))
                XCTAssertEqual(defaults.data(forKey: LocalEqualizerStore.storageKey), data)
            }
            defaults.set("wrong type", forKey: LocalEqualizerStore.storageKey)
            XCTAssertThrowsError(try store.save(valid))
            XCTAssertEqual(defaults.string(forKey: LocalEqualizerStore.storageKey), "wrong type")
        }
    }

    func testNameByteBoundaryAndDuplicatePersistedIDs() throws {
        try withDefaults { defaults in
            let store = LocalEqualizerStore(defaults: defaults)
            let saved = try store.save(.newCurve(name: String(repeating: "a", count: 212)))
            XCTAssertThrowsError(try store.save(.newCurve(name: String(repeating: "中", count: 71))))
            XCTAssertEqual(try store.load(), [saved])
            let duplicated = try JSONEncoder().encode([saved, saved])
            defaults.set(duplicated, forKey: LocalEqualizerStore.storageKey)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(defaults.data(forKey: LocalEqualizerStore.storageKey), duplicated)
        }
    }
}
