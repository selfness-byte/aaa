import Foundation
import Darwin

/// System memory metrics collected from Mach kernel and sysctl
public struct SystemMemoryMetrics: Sendable, Equatable {
    public let pageSize: UInt64
    public let wiredBytes: UInt64
    public let activeBytes: UInt64
    public let compressedBytes: UInt64
    public let freeExcludingSpeculativeBytes: UInt64
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapAvailBytes: UInt64

    public init(
        pageSize: UInt64,
        wiredBytes: UInt64,
        activeBytes: UInt64,
        compressedBytes: UInt64,
        freeExcludingSpeculativeBytes: UInt64,
        swapTotalBytes: UInt64,
        swapUsedBytes: UInt64,
        swapAvailBytes: UInt64
    ) {
        self.pageSize = pageSize
        self.wiredBytes = wiredBytes
        self.activeBytes = activeBytes
        self.compressedBytes = compressedBytes
        self.freeExcludingSpeculativeBytes = freeExcludingSpeculativeBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapAvailBytes = swapAvailBytes
    }
}

/// Production implementation of Darwin kernel queries for system statistics and process inspection.
public final class DarwinStatusCollector: ProcessIdentityProvider, @unchecked Sendable {

    /// Expected element count for host_statistics64(HOST_VM_INFO64)
    public static let hostVMInfo64Count: mach_msg_type_number_t = {
        return mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    }()

    public init() {}

    /// Queries host memory statistics (host_statistics64) and swap (sysctl vm.swapusage).
    /// Validates count of elements and buffer sizes strictly.
    public func collectSystemMemoryMetrics() -> SystemMemoryMetrics? {
        var pageSize: vm_size_t = 0
        let hostPort = mach_host_self()
        guard host_page_size(hostPort, &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return nil
        }
        let pSize = UInt64(pageSize)

        var vmStats = vm_statistics64_data_t()
        var count = DarwinStatusCollector.hostVMInfo64Count

        let kerr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        // Must succeed and count must be at least hostVMInfo64Count
        guard kerr == KERN_SUCCESS, count >= DarwinStatusCollector.hostVMInfo64Count else {
            return nil
        }

        let wired = UInt64(vmStats.wire_count) * pSize
        let active = UInt64(vmStats.active_count) * pSize
        let compressed = UInt64(vmStats.compressor_page_count) * pSize
        
        let freePages = vmStats.free_count > vmStats.speculative_count ? (vmStats.free_count - vmStats.speculative_count) : 0
        let freeExcludingSpeculative = UInt64(freePages) * pSize

        // Query Swap via sysctl vm.swapusage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let sysctlRes = sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        guard sysctlRes == 0, swapSize == MemoryLayout<xsw_usage>.size else {
            return nil
        }

        return SystemMemoryMetrics(
            pageSize: pSize,
            wiredBytes: wired,
            activeBytes: active,
            compressedBytes: compressed,
            freeExcludingSpeculativeBytes: freeExcludingSpeculative,
            swapTotalBytes: UInt64(swapUsage.xsu_total),
            swapUsedBytes: UInt64(swapUsage.xsu_used),
            swapAvailBytes: UInt64(swapUsage.xsu_avail)
        )
    }

    /// Queries Mach timebase information.
    public func queryMachTimebase() -> MachTimebase? {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS else {
            return nil
        }
        return MachTimebase(numer: info.numer, denom: info.denom)
    }

    /// Queries monotonic timestamp in nanoseconds using CLOCK_UPTIME_RAW.
    public func currentMonotonicNanoseconds() -> UInt64 {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    /// Queries kernel process identity via proc_pidinfo(PROC_PIDTBSDINFO).
    /// Validates returned byte count against MemoryLayout<proc_bsdinfo>.size.
    public func currentSnapshot(for instanceID: ExecutionInstanceID) -> ProcessIdentitySnapshot? {
        var bsdInfo = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.size
        let ret = proc_pidinfo(instanceID.pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(expectedSize))

        // Must receive full structure byte count
        guard ret == Int32(expectedSize) else {
            return nil
        }

        let startSec = UInt64(bsdInfo.pbi_start_tvsec)
        let startUsec = UInt64(bsdInfo.pbi_start_tvusec)

        let isAlive = (bsdInfo.pbi_status != UInt32(SZOMB))

        let readInstance = ExecutionInstanceID(
            pid: instanceID.pid,
            startTimeSec: startSec,
            startTimeUsec: startUsec
        )

        return ProcessIdentitySnapshot(
            instanceID: readInstance,
            uid: bsdInfo.pbi_uid,
            isAlive: isAlive
        )
    }

    /// Queries process cumulative CPU times via proc_pidinfo(PROC_PIDTASKINFO).
    /// Validates returned byte count against MemoryLayout<proc_taskinfo>.size.
    public func queryCPUTimeSample(for instanceID: ExecutionInstanceID, generationID: UInt64 = 0) -> CPUTimeSample? {
        var taskInfo = proc_taskinfo()
        let expectedSize = MemoryLayout<proc_taskinfo>.size
        let ret = proc_pidinfo(instanceID.pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(expectedSize))

        guard ret == Int32(expectedSize) else {
            return nil
        }

        let monotonicNs = currentMonotonicNanoseconds()

        return CPUTimeSample(
            pid: instanceID.pid,
            instanceStartTimeSec: instanceID.startTimeSec,
            instanceStartTimeUsec: instanceID.startTimeUsec,
            userCPUTimeMach: taskInfo.pti_total_user,
            systemCPUTimeMach: taskInfo.pti_total_system,
            monotonicTimeNanoseconds: monotonicNs,
            generationID: generationID
        )
    }
}
