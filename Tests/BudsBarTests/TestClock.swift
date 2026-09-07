import Foundation

/// Synthetic timing only: no fixture here represents captured device traffic.
final class TestClock {
    private struct Job {
        let deadline: TimeInterval
        let order: Int
        let action: () -> Void
    }

    private(set) var now: TimeInterval = 0
    private var jobs: [Job] = []
    private var nextOrder = 0

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        nextOrder += 1
        jobs.append(Job(deadline: now + delay, order: nextOrder, action: action))
    }

    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let index = jobs.indices.min(by: {
            let a = jobs[$0], b = jobs[$1]
            return a.deadline == b.deadline ? a.order < b.order : a.deadline < b.deadline
        }), jobs[index].deadline <= target {
            let job = jobs.remove(at: index)
            now = job.deadline
            job.action()
        }
        now = target
    }
}
