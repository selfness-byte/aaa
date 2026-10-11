import Foundation

// MARK: - Safe Chronology Formatter

public enum ChronologyFormatter {
    /// Safely formats relative elapsed time in seconds without UInt64 subtraction underflow.
    public static func format(observedNs: UInt64?, requestNs: UInt64) -> String {
        guard let obs = observedNs else { return "not observed" }
        guard obs >= requestNs else { return "precedes request" }
        let diffSec = Double(obs - requestNs) / 1e9
        return "\(String(format: "%.3f", diffSec))s"
    }
}

// MARK: - Thread-Safe Notification Tracker with Strict Per-PID Attribution

/// Tracks process lifecycle events strictly per PID to ensure notifications are attributed
/// exclusively to their originating process instance and prevent cross-instance readiness contamination.
public final class NotificationTracker: @unchecked Sendable {
    private var eventsByPID: [pid_t: UInt64] = [:]
    private let lock = NSLock()

    public init() {}

    /// Records an event timestamp for a specific process identifier.
    public func record(pid: pid_t, at time: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        eventsByPID[pid] = time
    }

    /// Checks if a notification was received specifically for the requested PID.
    public func isReceived(for pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventsByPID[pid] != nil
    }

    /// Retrieves the recorded timestamp for the requested PID, or nil if none was received.
    public func recordedTime(for pid: pid_t) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return eventsByPID[pid]
    }

    /// Clears recorded events for testing or reuse.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        eventsByPID.removeAll()
    }
}
