import BudsCore
import Foundation

/// Mac identity and content only: earbud slots and selection never enter storage.
struct LocalEqualizerScheme: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let gains: [Int8]

    var draft: CustomEqualizer? {
        guard let curve = CustomEqualizer.newCurve(name: name).replacingGains(gains),
              curve.payload(for: .create) != nil else { return nil }
        return curve
    }
}

final class LocalEqualizerStore {
    static let storageKey = "localEqualizerSchemes"
    private let defaults: UserDefaults

    enum StoreError: LocalizedError {
        case invalidCurve, invalidStorage
        var errorDescription: String? {
            switch self {
            case .invalidCurve: return "方案无效：名称不能为空且最多 212 字节，十段增益须在 ±6 dB 内。"
            case .invalidStorage: return "本地方案数据无法读取，原数据已保留，未覆盖或删除。"
            }
        }
    }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> [LocalEqualizerScheme] {
        guard let stored = defaults.object(forKey: Self.storageKey) else { return [] }
        guard let data = stored as? Data,
              let schemes = try? JSONDecoder().decode([LocalEqualizerScheme].self, from: data),
              schemes.allSatisfy({ $0.draft != nil }),
              Set(schemes.map(\.id)).count == schemes.count else { throw StoreError.invalidStorage }
        return schemes
    }

    @discardableResult
    func save(_ curve: CustomEqualizer) throws -> LocalEqualizerScheme {
        guard curve.writePayload != nil else { throw StoreError.invalidCurve }
        let scheme = LocalEqualizerScheme(id: UUID(), name: curve.name, gains: curve.gains)
        var schemes = try load()
        schemes.append(scheme)
        try persist(schemes)
        return scheme
    }

    func delete(id: UUID) throws {
        var schemes = try load()
        schemes.removeAll { $0.id == id }
        try persist(schemes)
    }

    private func persist(_ schemes: [LocalEqualizerScheme]) throws {
        let data = try JSONEncoder().encode(schemes)
        defaults.set(data, forKey: Self.storageKey)
    }
}
