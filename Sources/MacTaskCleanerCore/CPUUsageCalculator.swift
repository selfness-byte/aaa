import Foundation

/// Mach timebase conversion info (numer / denom).
/// Requires both numer > 0 and denom > 0 to be valid.
public struct MachTimebase: Sendable, Equatable {
    public let numer: UInt32
    public let denom: UInt32

    public init?(numer: UInt32, denom: UInt32) {
        guard numer > 0, denom > 0 else {
            return nil
        }
        self.numer = numer
        self.denom = denom
    }

    /// Converts Mach absolute time ticks into nanoseconds with 100% exact integer arithmetic.
    ///
    /// Uses 128-bit full-width multiplication and division via Swift standard library:
    /// - (high, low) = machTicks * numer (128-bit product)
    /// - Checks if high >= denom: if true, quotient >= 2^64 (overflows UInt64), returns nil.
    /// - If high < denom, divides full-width without trapping, yielding exact 64-bit integer nanoseconds.
    public func toNanoseconds(machTicks: UInt64) -> UInt64? {
        if numer == denom {
            return machTicks
        }
        let d = UInt64(denom)
        let (high, low) = machTicks.multipliedFullWidth(by: UInt64(numer))

        // If high >= d, the mathematical quotient is >= 2^64, which overflows UInt64.
        guard high < d else {
            return nil
        }

        let (quotient, _) = d.dividingFullWidth((high: high, low: low))
        return quotient
    }
}

/// Snapshot of CPU times for a specific execution instance at a specific monotonic timestamp.
public struct CPUTimeSample: Sendable, Equatable {
    public let pid: pid_t
    public let instanceStartTimeSec: UInt64
    public let instanceStartTimeUsec: UInt64
    public let userCPUTimeMach: UInt64
    public let systemCPUTimeMach: UInt64
    public let monotonicTimeNanoseconds: UInt64
    public let generationID: UInt64 // Used for sleep/wake or baseline resets

    public init(
        pid: pid_t,
        instanceStartTimeSec: UInt64,
        instanceStartTimeUsec: UInt64,
        userCPUTimeMach: UInt64,
        systemCPUTimeMach: UInt64,
        monotonicTimeNanoseconds: UInt64,
        generationID: UInt64 = 0
    ) {
        self.pid = pid
        self.instanceStartTimeSec = instanceStartTimeSec
        self.instanceStartTimeUsec = instanceStartTimeUsec
        self.userCPUTimeMach = userCPUTimeMach
        self.systemCPUTimeMach = systemCPUTimeMach
        self.monotonicTimeNanoseconds = monotonicTimeNanoseconds
        self.generationID = generationID
    }
}

/// Reason why CPU usage calculation could not be computed from two samples.
public enum SampleRejectionReason: Sendable, Equatable {
    case instanceMismatch
    case generationMismatch
    case nonPositiveElapsedTime(deltaNs: Int64)
    case counterRollback(userRollback: Bool, systemRollback: Bool)
    case arithmeticOverflow
}

/// Result of evaluating two CPU time samples.
public enum CPUCalculationResult: Sendable, Equatable {
    case valid(percentage: Double)
    case rejected(reason: SampleRejectionReason)
}

/// Pure computation engine for CPU usage calculations.
public struct CPUUsageCalculator: Sendable {
    public let timebase: MachTimebase

    public init(timebase: MachTimebase) {
        self.timebase = timebase
    }

    /// Calculates CPU usage percentage based on two consecutive samples.
    ///
    /// Formula:
    /// delta_CPU_ns = (delta_User_Mach + delta_System_Mach) * (numer / denom)
    /// CPU% = (delta_CPU_ns / delta_Monotonic_ns) * 100.0
    ///
    /// Preserves values > 100.0% for multi-threaded processes (single core 100% baseline).
    public func calculateUsage(
        previous: CPUTimeSample,
        current: CPUTimeSample
    ) -> CPUCalculationResult {
        // 1. Verify exact execution instance identity
        guard previous.pid == current.pid,
              previous.instanceStartTimeSec == current.instanceStartTimeSec,
              previous.instanceStartTimeUsec == current.instanceStartTimeUsec else {
            return .rejected(reason: .instanceMismatch)
        }

        // 2. Verify generation matches (detects sleep/wake baseline resets)
        guard previous.generationID == current.generationID else {
            return .rejected(reason: .generationMismatch)
        }

        // 3. Verify monotonic elapsed time is strictly positive
        guard current.monotonicTimeNanoseconds > previous.monotonicTimeNanoseconds else {
            let nonPosDelta: Int64
            if current.monotonicTimeNanoseconds == previous.monotonicTimeNanoseconds {
                nonPosDelta = 0
            } else {
                let diff = previous.monotonicTimeNanoseconds - current.monotonicTimeNanoseconds
                nonPosDelta = diff <= UInt64(Int64.max) ? -Int64(diff) : Int64.min
            }
            return .rejected(reason: .nonPositiveElapsedTime(deltaNs: nonPosDelta))
        }

        let elapsedDeltaNs = current.monotonicTimeNanoseconds - previous.monotonicTimeNanoseconds

        // 4. Verify CPU counters did not roll back
        let userRollback = current.userCPUTimeMach < previous.userCPUTimeMach
        let systemRollback = current.systemCPUTimeMach < previous.systemCPUTimeMach
        guard !userRollback && !systemRollback else {
            return .rejected(reason: .counterRollback(userRollback: userRollback, systemRollback: systemRollback))
        }

        let deltaUserMach = current.userCPUTimeMach - previous.userCPUTimeMach
        let deltaSystemMach = current.systemCPUTimeMach - previous.systemCPUTimeMach

        // 5. Safe Mach ticks summation with overflow detection
        let (totalDeltaMach, sumOverflow) = deltaUserMach.addingReportingOverflow(deltaSystemMach)
        guard !sumOverflow else {
            return .rejected(reason: .arithmeticOverflow)
        }

        // 6. Convert to nanoseconds via Mach timebase with exact integer arithmetic
        guard let totalDeltaCPU_ns = timebase.toNanoseconds(machTicks: totalDeltaMach) else {
            return .rejected(reason: .arithmeticOverflow)
        }

        // 7. Calculate percentage safely
        let percentage = (Double(totalDeltaCPU_ns) / Double(elapsedDeltaNs)) * 100.0
        guard !percentage.isNaN, !percentage.isInfinite, percentage >= 0.0 else {
            return .rejected(reason: .arithmeticOverflow)
        }

        return .valid(percentage: percentage)
    }
}
