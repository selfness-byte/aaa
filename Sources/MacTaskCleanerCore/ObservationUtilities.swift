import Foundation

// MARK: - Safe Chronology Formatter

public enum ChronologyFormatter {
    /// Formats relative chronology time with observed nanoseconds and request nanoseconds.
    /// Safely handles unobserved timestamps (nil) and out-of-order timestamps without UInt64 subtraction underflow.
    public static func format(observedNs: UInt64?, requestNs: UInt64) -> String {
        guard let obs = observedNs else {
            return "not observed within wait window"
        }
        guard obs >= requestNs else {
            let diffSec = Double(requestNs - obs) / 1e9
            return "\(obs) ns (precedes request by \(String(format: "%.3f", diffSec))s)"
        }
        let diffSec = Double(obs - requestNs) / 1e9
        return "\(obs) ns (\(String(format: "%.3f", diffSec))s)"
    }
}

// MARK: - Target Confinement Guard

public enum TargetConfinementGuard {
    /// Strictly verifies whether a target PID, bundle identifier, and standardized path match allowed target parameters.
    public static func validate(
        targetPID: pid_t,
        allowedPID: pid_t,
        targetBundleID: String?,
        expectedBundleID: String,
        targetBundlePath: String?,
        expectedBundlePath: String
    ) -> Bool {
        guard targetPID == allowedPID else { return false }
        guard let bID = targetBundleID, bID == expectedBundleID else { return false }
        guard let path = targetBundlePath, path == expectedBundlePath else { return false }
        return true
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
