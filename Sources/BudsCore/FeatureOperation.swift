import Foundation

public enum ControlFeature: Hashable { case noise, equalizer, gameMode }

public enum OperationTarget: Equatable {
    case noise(NoiseMode, ANCLevel?)
    case equalizer(EQPreset)
    case customEqualizer(CustomEqualizer)
    case customEQManagement(CustomEQAction, CustomEqualizer, Set<UInt8>)
    case gameMode(Bool)
}

public enum OperationPhase: Equatable {
    case queued, sent, confirmed, differentState, timedOut, sendFailed, cancelled

    public var isPending: Bool { self == .queued || self == .sent }

    public var message: String? {
        switch self {
        case .differentState: return "耳机返回的状态与请求不同，请重新读取后确认"
        case .timedOut: return "未能确认设置结果，请重新读取或手动重试"
        case .sendFailed: return "设置未能发送"
        case .cancelled: return "连接已中断，设置结果未确认"
        default: return nil
        }
    }
}

public struct FeatureOperation: Equatable {
    public let id: UInt64
    public let generation: UInt64
    public let target: OperationTarget
    public var phase: OperationPhase
    public var sentAt: TimeInterval?
    public var deadline: TimeInterval?
}
