import Foundation

/// Bound UI publications, not measurements: retain the latest real progress value.
nonisolated final class DownloadProgressCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (Double?, String?)?
    private var scheduled = false
    private var generation: UInt64 = 0
    private var lastSubmissionWasMeasured: Bool?
    private let interval: TimeInterval
    private let deliver: @MainActor @Sendable (Double?, String?) -> Void

    init(interval: TimeInterval = 0.1, deliver: @escaping @MainActor @Sendable (Double?, String?) -> Void) {
        self.interval = interval
        self.deliver = deliver
    }

    func submit(_ progress: Double?, _ speed: String?) {
        lock.lock()
        pending = (progress, speed)
        let isMeasured = progress?.isFinite == true
        // First feedback and measurement transitions must not wait behind the throttle.
        let immediate = lastSubmissionWasMeasured != isMeasured || progress == 1
        lastSubmissionWasMeasured = isMeasured
        guard immediate || !scheduled else {
            lock.unlock()
            return
        }
        generation &+= 1
        let token = generation
        scheduled = true
        lock.unlock()
        if immediate {
            DispatchQueue.main.async { self.flush(generation: token) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { self.flush(generation: token) }
        }
    }

    @MainActor private func flush(generation token: UInt64) {
        lock.lock()
        guard scheduled, generation == token else {
            lock.unlock()
            return
        }
        let value = pending
        pending = nil
        scheduled = false
        lock.unlock()
        if let value { deliver(value.0, value.1) }
    }
}
