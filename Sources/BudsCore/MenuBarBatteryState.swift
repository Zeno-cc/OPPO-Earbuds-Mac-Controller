import Foundation

/// The last observation for one vendor-reported battery slot.
/// `reading == nil` is an explicit unknown, not an absent slot.
public struct BatterySlotObservation: Equatable {
    public let reading: BatteryReading?
    public let generation: UInt64
    public let observedAt: TimeInterval

    public init(reading: BatteryReading?, generation: UInt64, observedAt: TimeInterval) {
        self.reading = reading
        self.generation = generation
        self.observedAt = observedAt
    }
}
