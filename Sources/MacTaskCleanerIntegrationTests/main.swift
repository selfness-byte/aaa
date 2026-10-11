import AppKit
import Foundation
import MacTaskCleanerCore

// MARK: - Confinement-Guarded Live App Terminator

/// An AppTerminator that strictly limits termination requests ONLY to the specific
/// DummyTestTarget.app instance launched during the current test execution.
final class DummyAppTerminator: AppTerminator, @unchecked Sendable {
    let allowedPID: pid_t
    let allowedBundleID = "com.mactaskcleaner.dummytesttarget"
    let expectedBundleURL: URL
    let runningApp: NSRunningApplication
    private(set) var requestTerminateCallCount = 0
    private(set) var lastRequestReturn: Bool?
    private(set) var lastRequestTimeNs: UInt64 = 0

    init(runningApp: NSRunningApplication, expectedBundleURL: URL) {
        self.runningApp = runningApp
        self.allowedPID = runningApp.processIdentifier
        self.expectedBundleURL = expectedBundleURL.standardizedFileURL
    }

    func isAlreadyTerminated(instanceID: ExecutionInstanceID) -> Bool {
        // Strict contract: PID mismatch is NOT "already terminated"!
        // Mismatch must return false so state machine pre-flight checks fail closed with .instanceMismatch.
        guard instanceID.pid == allowedPID else { return false }
        return runningApp.isTerminated
    }

    func requestTerminate(instanceID: ExecutionInstanceID) -> Bool {
        // Strict confinement checks:
        // 1. PID must match the exact instance launched for this test
        // 2. NSRunningApplication instance must match allowedPID
        // 3. Bundle identifier must match DummyTestTarget
        // 4. Standardized Bundle URL path must match expectedBundleURL exactly
        // 5. Must not already be terminated
        guard instanceID.pid == allowedPID,
              runningApp.processIdentifier == allowedPID,
              runningApp.bundleIdentifier == allowedBundleID,
              let appPath = runningApp.bundleURL?.standardizedFileURL.path,
              appPath == expectedBundleURL.path,
              !runningApp.isTerminated else {
            return false
        }
        requestTerminateCallCount += 1
        lastRequestTimeNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let ret = runningApp.terminate()
        lastRequestReturn = ret
        return ret
    }

    func checkQuickTermination(instanceID: ExecutionInstanceID) -> Bool {
        guard instanceID.pid == allowedPID else { return false }
        return runningApp.isTerminated
    }
}

// MARK: - Mock Protection Checker for Integration

final class MockIntegrationProtectionChecker: ProtectionChecker, @unchecked Sendable {
    func checkProtection(for instanceID: ExecutionInstanceID) -> ProtectionCheckResult {
        return .unprotected
    }
}

// MARK: - Integration Test Runner

@MainActor
final class IntegrationTestRunner {
    private var passedCount = 0
    private var failedCount = 0

    func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) {
        if condition() {
            passedCount += 1
        } else {
            failedCount += 1
            print("❌ [FAILED] Assertion failed at \(file):\(line): \(message)")
        }
    }

    func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) {
        if !condition() {
            passedCount += 1
        } else {
            failedCount += 1
            print("❌ [FAILED] Assertion failed (expected false) at \(file):\(line): \(message)")
        }
    }

    func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
        if actual == expected {
            passedCount += 1
        } else {
            failedCount += 1
            print("❌ [FAILED] Expected [\(expected)], got [\(actual)] at \(file):\(line): \(message)")
        }
    }

    func printPass(_ testName: String) {
        print("  ✅ [PASS] \(testName)")
    }

    func runTest(_ name: String, block: () async throws -> Void) async {
        do {
            let startFailures = failedCount
            try await block()
            if failedCount == startFailures {
                printPass(name)
            }
        } catch {
            failedCount += 1
            print("  💥 [ERROR] \(name) threw error: \(error)")
        }
    }

    /// Safe subtraction helper to avoid UInt64 underflow and Signal 4 crash when formatting event chronology.
    func formatChronologyTime(observedNs: UInt64?, requestNs: UInt64) -> String {
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

    /// Runs the main run loop in default mode to process input sources and timer events up to a deadline,
    /// enabling AppKit IPC and notification dispatches during synchronization waits.
    func pumpRunLoop(duration: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: duration)
        while Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
    }

    /// Synchronizes DummyTestTarget executable into DummyTestTarget.app bundle with strict error checking.
    func ensureAppBundle(at bundleDir: URL) throws {
        let productsDir = bundleDir.deletingLastPathComponent()
        let execSrc = productsDir.appendingPathComponent("DummyTestTarget")
        let macOSDir = bundleDir.appendingPathComponent("Contents/MacOS")
        let execDst = macOSDir.appendingPathComponent("DummyTestTarget")
        let plistDst = bundleDir.appendingPathComponent("Contents/Info.plist")

        let fm = FileManager.default

        guard fm.fileExists(atPath: execSrc.path) else {
            throw NSError(domain: "BundlePrepError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Source DummyTestTarget binary not found at \(execSrc.path). Build target DummyTestTarget first."
            ])
        }

        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: execDst.path) {
            try fm.removeItem(at: execDst)
        }
        try fm.copyItem(at: execSrc, to: execDst)

        guard fm.isExecutableFile(atPath: execDst.path) else {
            throw NSError(domain: "BundlePrepError", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Destination binary is not executable at \(execDst.path)"
            ])
        }

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.mactaskcleaner.dummytesttarget</string>
            <key>CFBundleName</key>
            <string>DummyTestTarget</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleExecutable</key>
            <string>DummyTestTarget</string>
            <key>LSUIElement</key>
            <false/>
        </dict>
        </plist>
        """
        try plistContent.write(to: plistDst, atomically: true, encoding: .utf8)

        guard fm.fileExists(atPath: plistDst.path) else {
            throw NSError(domain: "BundlePrepError", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Info.plist failed to write at \(plistDst.path)"
            ])
        }
    }

    /// Launches DummyTestTarget.app strictly using NSWorkspace.shared.openApplication and ensures readiness.
    func launchDummyApp(appURL: URL, arguments: [String] = []) async throws -> (app: NSRunningApplication, notificationReceived: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        if !arguments.isEmpty {
            config.arguments = arguments
        }

        let launchTracker = NotificationTracker()

        let launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notif in
            if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "com.mactaskcleaner.dummytesttarget" {
                launchTracker.record(pid: app.processIdentifier, at: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
            }
        }
        defer {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }

        let app: NSRunningApplication = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSRunningApplication, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let app = app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: NSError(domain: "LaunchError", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "openApplication returned nil app and nil error"
                    ]))
                }
            }
        }

        let targetPID = app.processIdentifier

        // Wait until app has finished its AppKit launch cycle (confirmed via notification or isFinishedLaunching)
        let launchDeadline = Date(timeIntervalSinceNow: 8.0)
        while Date() < launchDeadline && !app.isFinishedLaunching && !launchTracker.isReceived(for: targetPID) {
            self.pumpRunLoop(duration: 0.05)
        }

        let notifReceived = launchTracker.isReceived(for: targetPID)
        guard app.isFinishedLaunching || notifReceived else {
            throw NSError(domain: "LaunchError", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "DummyTestTarget.app failed to complete AppKit launch within 8.0s deadline"
            ])
        }

        return (app, notifReceived)
    }

    func runAll() async {
        print("==================================================")
        print("🚀 Running MacTaskCleaner Phase 3: macOS Integration Tests")
        print("==================================================")

        _ = NSApplication.shared // Ensure AppKit environment is active in test runner

        let startTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let collector = DarwinStatusCollector()

        // Locate DummyTestTarget.app bundle inside Products directory
        let bundleURL = Bundle.main.bundleURL
        let productsURL: URL
        if bundleURL.pathExtension == "xctest" || bundleURL.pathExtension == "app" {
            productsURL = bundleURL.deletingLastPathComponent()
        } else {
            productsURL = bundleURL
        }
        let bundleDir = productsURL.appendingPathComponent("DummyTestTarget.app")

        do {
            try self.ensureAppBundle(at: bundleDir)
            print("📍 DummyTestTarget.app verified at: \(bundleDir.path)")
        } catch {
            print("❌ Failed to verify/package DummyTestTarget.app bundle: \(error)")
            exit(1)
        }

        // MARK: - Test 1: Read-Only Darwin Kernel Metrics, Timebase & CPU Sample Link
        await runTest("Test 1: Read-Only System Metrics, Mach Timebase & CPU Sample Link") {
            // 1a. Memory & Swap
            guard let metrics = collector.collectSystemMemoryMetrics() else {
                self.assertTrue(false, "collectSystemMemoryMetrics returned nil")
                return
            }

            self.assertTrue(metrics.pageSize > 0, "Page size must be positive")
            self.assertTrue(metrics.wiredBytes > 0, "Wired memory must be positive")
            self.assertTrue(metrics.activeBytes > 0, "Active memory must be positive")
            self.assertTrue(metrics.freeExcludingSpeculativeBytes > 0, "Free memory must be positive")
            self.assertTrue(DarwinStatusCollector.hostVMInfo64Count > 0, "hostVMInfo64Count must be positive element count")
            print("    [Info] Mach PageSize: \(metrics.pageSize) bytes")
            print("    [Info] Wired: \(metrics.wiredBytes / (1024*1024)) MB, Active: \(metrics.activeBytes / (1024*1024)) MB, Compressed: \(metrics.compressedBytes / (1024*1024)) MB")
            print("    [Info] Swap Total: \(metrics.swapTotalBytes / (1024*1024)) MB, Used: \(metrics.swapUsedBytes / (1024*1024)) MB, Avail: \(metrics.swapAvailBytes / (1024*1024)) MB")

            // 1b. Timebase & Monotonic Clock
            guard let timebase = collector.queryMachTimebase() else {
                self.assertTrue(false, "queryMachTimebase returned nil")
                return
            }
            self.assertTrue(timebase.numer > 0 && timebase.denom > 0, "Timebase must have positive numer and denom")
            print("    [Info] Mach Timebase: \(timebase.numer)/\(timebase.denom)")

            let t1 = collector.currentMonotonicNanoseconds()
            self.pumpRunLoop(duration: 0.05)
            let t2 = collector.currentMonotonicNanoseconds()
            self.assertTrue(t2 > t1, "Monotonic clock must strictly advance")

            // 1c. Self-process CPU Sample via PROC_PIDTASKINFO & Calculator Link
            let selfPID = ProcessInfo.processInfo.processIdentifier
            let selfProbeID = ExecutionInstanceID(pid: selfPID, startTimeSec: 0, startTimeUsec: 0)
            guard let selfSample1 = collector.queryCPUTimeSample(for: selfProbeID) else {
                self.assertTrue(false, "Failed to query CPU time sample for self")
                return
            }
            self.assertEqual(selfSample1.pid, selfPID)
            self.assertTrue(selfSample1.monotonicTimeNanoseconds > 0)

            // Deliberate compute workload on test runner thread to advance CPU ticks
            var dummySum: UInt64 = 0
            for i: UInt64 in 0..<500_000 {
                dummySum &+= (i &* 3)
            }
            _ = dummySum

            guard let selfSample2 = collector.queryCPUTimeSample(for: selfProbeID) else {
                self.assertTrue(false, "Failed to query CPU time sample 2 for self")
                return
            }
            self.assertTrue(selfSample2.monotonicTimeNanoseconds > selfSample1.monotonicTimeNanoseconds)
            self.assertTrue(selfSample2.userCPUTimeMach >= selfSample1.userCPUTimeMach)

            let deltaUser = selfSample2.userCPUTimeMach - selfSample1.userCPUTimeMach
            let deltaSys = selfSample2.systemCPUTimeMach - selfSample1.systemCPUTimeMach
            let deltaMonoNs = selfSample2.monotonicTimeNanoseconds - selfSample1.monotonicTimeNanoseconds

            print("    [CPU Derivation] Sample 1: UserTicks=\(selfSample1.userCPUTimeMach), SysTicks=\(selfSample1.systemCPUTimeMach), t1=\(selfSample1.monotonicTimeNanoseconds) ns")
            print("    [CPU Derivation] Sample 2: UserTicks=\(selfSample2.userCPUTimeMach), SysTicks=\(selfSample2.systemCPUTimeMach), t2=\(selfSample2.monotonicTimeNanoseconds) ns")
            print("    [CPU Derivation] ΔUserTicks=\(deltaUser), ΔSysTicks=\(deltaSys), ΔMonotonicNs=\(deltaMonoNs) ns, Timebase=\(timebase.numer)/\(timebase.denom)")

            let calculator = CPUUsageCalculator(timebase: timebase)
            let calcResult = calculator.calculateUsage(previous: selfSample1, current: selfSample2)
            switch calcResult {
            case .valid(let pct):
                self.assertTrue(pct >= 0.0, "Calculated CPU percentage must be non-negative: \(pct)%")
                print("    [CPU Derivation] Calculated CPU Usage: \(String(format: "%.2f", pct))% (Deliberate runner-thread loop, not idle measurement)")
            case .rejected(let reason):
                self.assertTrue(false, "CPUUsageCalculator rejected live samples: \(reason)")
            }

            // Fail-safe: Non-existent PID returns nil
            let invalidID = ExecutionInstanceID(pid: 999_999, startTimeSec: 0, startTimeUsec: 0)
            let invalidSnapshot = collector.currentSnapshot(for: invalidID)
            self.assertEqual(invalidSnapshot, nil, "Querying non-existent PID must fail-safe and return nil")

            let invalidCPUSample = collector.queryCPUTimeSample(for: invalidID)
            self.assertEqual(invalidCPUSample, nil, "Querying CPU for non-existent PID must return nil")
        }

        // MARK: - Test 2: Kernel CPU Sample Start Time Verification (proc_pidinfo PROC_PIDTBSDINFO)
        await runTest("Test 2: Kernel CPU Sample Start Time Verification (proc_pidinfo PROC_PIDTBSDINFO)") {
            let selfPID = ProcessInfo.processInfo.processIdentifier
            let probeID = ExecutionInstanceID(pid: selfPID, startTimeSec: 0, startTimeUsec: 0)
            guard let realSnapshot = collector.currentSnapshot(for: probeID) else {
                self.assertTrue(false, "Failed to get real snapshot for self")
                return
            }

            // Valid sample with real start time should succeed
            let validSample = collector.queryCPUTimeSample(for: realSnapshot.instanceID)
            self.assertTrue(validSample != nil, "Query with exact kernel start time must succeed")

            // Stale sample with altered start time must be rejected (returns nil)
            let staleInstance = ExecutionInstanceID(
                pid: selfPID,
                startTimeSec: realSnapshot.instanceID.startTimeSec &+ 9999,
                startTimeUsec: realSnapshot.instanceID.startTimeUsec
            )
            let staleSample = collector.queryCPUTimeSample(for: staleInstance)
            self.assertEqual(staleSample, nil, "Query with stale/mismatched start time MUST return nil")
        }

        // MARK: - Test 3: Launch Dummy App (Real AppKit .app) & Kernel Identity Inspection
        var launchedDummy1: NSRunningApplication?
        var instance1: ExecutionInstanceID?

        await runTest("Test 3: Launch Dummy App (AppKit Bundle) & Query Darwin Process Info") {
            let (app, launchNotif) = try await self.launchDummyApp(appURL: bundleDir)
            launchedDummy1 = app
            let pid = app.processIdentifier

            self.assertEqual(app.bundleIdentifier, "com.mactaskcleaner.dummytesttarget")
            self.assertEqual(app.activationPolicy, .regular, "Dummy app must have .regular activation policy")
            self.assertTrue(app.isFinishedLaunching || launchNotif, "Dummy app must be confirmed finished launching")
            self.assertTrue(pid > 0, "PID must be positive")

            // Probe start time from kernel BSD info (proc_pidinfo PROC_PIDTBSDINFO)
            let probeID = ExecutionInstanceID(pid: pid, startTimeSec: 0, startTimeUsec: 0)
            guard let initialSnapshot = collector.currentSnapshot(for: probeID) else {
                self.assertTrue(false, "Failed to get initial snapshot for dummy app")
                return
            }

            self.assertEqual(initialSnapshot.instanceID.pid, pid)
            self.assertEqual(initialSnapshot.uid, getuid(), "UID must match current user")
            self.assertTrue(initialSnapshot.isAlive, "Launched dummy process must be alive")
            self.assertTrue(initialSnapshot.instanceID.startTimeSec > 0, "Start time must be non-zero")

            instance1 = initialSnapshot.instanceID
            print("    [Info] Dummy 1 launched: PID=\(pid), StartTimeSec=\(initialSnapshot.instanceID.startTimeSec), UID=\(initialSnapshot.uid), Policy=.regular, isFinishedLaunching=\(app.isFinishedLaunching), launchNotif=\(launchNotif)")

            // Query CPU sample via proc_pidinfo(PROC_PIDTASKINFO)
            guard let cpuSample = collector.queryCPUTimeSample(for: initialSnapshot.instanceID) else {
                self.assertTrue(false, "Failed to query CPU time sample for dummy app")
                return
            }
            self.assertEqual(cpuSample.pid, pid)
            self.assertTrue(cpuSample.monotonicTimeNanoseconds > 0)
        }

        // MARK: - Test 4: Graceful Termination of Dummy App via AppKit & Event Chronology
        await runTest("Test 4: Graceful Termination of Dummy App via AppKit & Event Chronology") {
            guard let app = launchedDummy1, let inst = instance1 else {
                self.assertTrue(false, "Missing launched dummy app from Test 3")
                return
            }

            let stateMachine = TerminationStateMachine()
            let protection = MockIntegrationProtectionChecker()
            let terminator = DummyAppTerminator(runningApp: app, expectedBundleURL: bundleDir)

            let tracker = NotificationTracker()

            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { notif in
                if let termApp = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   termApp.processIdentifier == inst.pid,
                   termApp == app { // Reference equality check on the specific launched instance
                    let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                    tracker.record(pid: termApp.processIdentifier, at: nowNs)
                    Task {
                        await stateMachine.handleTerminationObserved(instanceID: inst)
                    }
                }
            }

            let tReq = collector.currentMonotonicNanoseconds()

            // Initiate termination through state machine
            let initResult = await stateMachine.initiateTermination(
                targetInstance: inst,
                allowedUID: getuid(),
                identityProvider: collector,
                protectionChecker: protection,
                terminator: terminator
            )

            self.assertEqual(terminator.requestTerminateCallCount, 1)
            self.assertEqual(terminator.lastRequestReturn, true, "runningApp.terminate() must return true")
            self.assertTrue(initResult.requestID != nil)

            // Pump RunLoop until termination observed or timeout (max 5s)
            var tTermObserved: UInt64? = app.isTerminated ? collector.currentMonotonicNanoseconds() : nil
            let waitDeadline = Date(timeIntervalSinceNow: 5.0)
            while Date() < waitDeadline && !app.isTerminated {
                self.pumpRunLoop(duration: 0.05)
                if app.isTerminated && tTermObserved == nil {
                    tTermObserved = collector.currentMonotonicNanoseconds()
                }
            }
            if app.isTerminated && tTermObserved == nil {
                tTermObserved = collector.currentMonotonicNanoseconds()
            }

            // Pump briefly to let async actor state update
            self.pumpRunLoop(duration: 0.1)

            NSWorkspace.shared.notificationCenter.removeObserver(observer)

            let elapsedTotalSec = Double(collector.currentMonotonicNanoseconds() - tReq) / 1_000_000_000.0

            self.assertTrue(app.isTerminated, "Dummy app must be confirmed terminated")
            self.assertTrue(tracker.isReceived(for: inst.pid), "didTerminateApplicationNotification must be received on NSWorkspace.shared.notificationCenter")
            self.assertTrue(elapsedTotalSec < 10.0, "Termination must occur well before fallback timeout")

            let finalState = await stateMachine.getState(for: inst)
            switch finalState {
            case .confirmed(let source):
                self.assertTrue(true, "Final state is confirmed via \(source)")
                print("    [Chronology] Request Sent: \(tReq) ns")
                print("    [Chronology] Terminate Return: true")
                print("    [Chronology] isTerminated Observed: \(self.formatChronologyTime(observedNs: tTermObserved, requestNs: tReq))")
                print("    [Chronology] Notification Received: \(self.formatChronologyTime(observedNs: tracker.isReceived(for: inst.pid) ? tracker.recordedTime(for: inst.pid) : nil, requestNs: tReq))")
                print("    [Chronology] Final State: .confirmed(\(source))")
            default:
                self.assertTrue(false, "Expected .confirmed, got \(finalState)")
            }

            let isObserved = await stateMachine.isObservedTerminated(instanceID: inst)
            self.assertTrue(isObserved)
        }

        // MARK: - Test 5: Delayed Termination of Dummy App (Timeout -> Late Termination)
        await runTest("Test 5: Delayed Termination of Dummy App (Timeout -> Late Confirmation)") {
            // Launch dummy app with --delay-terminate argument
            let (appDelayed, delayedLaunchNotif) = try await self.launchDummyApp(appURL: bundleDir, arguments: ["--delay-terminate"])
            let pidDelayed = appDelayed.processIdentifier

            let probeID = ExecutionInstanceID(pid: pidDelayed, startTimeSec: 0, startTimeUsec: 0)
            guard let snapDelayed = collector.currentSnapshot(for: probeID) else {
                self.assertTrue(false, "Failed to get snapshot for delayed dummy app")
                return
            }
            let instDelayed = snapDelayed.instanceID
            print("    [Info] Dummy Delayed launched: PID=\(pidDelayed), StartTimeSec=\(instDelayed.startTimeSec), isFinishedLaunching=\(appDelayed.isFinishedLaunching), launchNotif=\(delayedLaunchNotif)")

            let stateMachine = TerminationStateMachine()
            let protection = MockIntegrationProtectionChecker()
            let terminator = DummyAppTerminator(runningApp: appDelayed, expectedBundleURL: bundleDir)

            let delayedTracker = NotificationTracker()

            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { notif in
                if let termApp = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   termApp.processIdentifier == pidDelayed,
                   termApp == appDelayed { // Reference equality check
                    let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                    delayedTracker.record(pid: termApp.processIdentifier, at: nowNs)
                    Task {
                        await stateMachine.handleTerminationObserved(instanceID: instDelayed)
                    }
                }
            }

            let tReq = collector.currentMonotonicNanoseconds()

            // Initiate termination
            let initResult = await stateMachine.initiateTermination(
                targetInstance: instDelayed,
                allowedUID: getuid(),
                identityProvider: collector,
                protectionChecker: protection,
                terminator: terminator
            )
            guard let reqID = initResult.requestID else {
                self.assertTrue(false, "Failed to get requestID for delayed termination")
                return
            }
            self.assertEqual(initResult.finalState, .awaitingTermination)

            // Pump RunLoop for 0.3s. Because dummy delays by 1.2s, it is STILL RUNNING!
            self.pumpRunLoop(duration: 0.3)
            self.assertFalse(appDelayed.isTerminated, "Dummy should still be alive during delay period")

            // Simulate timeout expiry at 0.3s
            let tTimeout = collector.currentMonotonicNanoseconds()
            await stateMachine.handleTimeout(instanceID: instDelayed, requestID: reqID)

            let timeoutState = await stateMachine.getState(for: instDelayed)
            self.assertEqual(timeoutState, .unconfirmedWithinTimeout, "State must transition to unconfirmedWithinTimeout upon timeout")
            self.assertFalse(appDelayed.isTerminated, "Must NOT forceTerminate or kill the app!")

            print("    [Chronology] Request Sent: \(tReq) ns")
            print("    [Chronology] Timeout Reached at: \(tTimeout) ns -> State: .unconfirmedWithinTimeout (No force terminate invoked)")

            // Continue pumping RunLoop until dummy app finishes its delay and terminates (up to 4.0s)
            var tLateTermObserved: UInt64? = nil
            let waitDeadline = Date(timeIntervalSinceNow: 4.0)
            while Date() < waitDeadline && !appDelayed.isTerminated {
                self.pumpRunLoop(duration: 0.05)
                if appDelayed.isTerminated && tLateTermObserved == nil {
                    tLateTermObserved = collector.currentMonotonicNanoseconds()
                }
            }
            if appDelayed.isTerminated && tLateTermObserved == nil {
                tLateTermObserved = collector.currentMonotonicNanoseconds()
            }

            // Pump briefly to let async actor state update
            self.pumpRunLoop(duration: 0.1)

            NSWorkspace.shared.notificationCenter.removeObserver(observer)

            self.assertTrue(appDelayed.isTerminated, "Dummy app must eventually terminate after delay")
            self.assertTrue(delayedTracker.isReceived(for: instDelayed.pid), "Notification must be received on NSWorkspace.shared.notificationCenter")

            let finalState = await stateMachine.getState(for: instDelayed)
            self.assertEqual(finalState, .confirmed(source: .lateNotification), "State must update to confirmed(.lateNotification)")

            let isObserved = await stateMachine.isObservedTerminated(instanceID: instDelayed)
            self.assertTrue(isObserved)

            print("    [Chronology] Late isTerminated Observed: \(self.formatChronologyTime(observedNs: tLateTermObserved, requestNs: tReq))")
            print("    [Chronology] Late Notification Received: \(self.formatChronologyTime(observedNs: delayedTracker.isReceived(for: instDelayed.pid) ? delayedTracker.recordedTime(for: instDelayed.pid) : nil, requestNs: tReq))")
            print("    [Chronology] Final State Transition: .confirmed(.lateNotification)")
        }

        // MARK: - Test 6: Respawn / New Execution Isolation
        await runTest("Test 6: Respawn / New Execution Isolation") {
            guard let oldInst = instance1 else {
                self.assertTrue(false, "Missing old instance")
                return
            }

            // Launch 2nd dummy instance
            let (app2, app2LaunchNotif) = try await self.launchDummyApp(appURL: bundleDir)
            let pid2 = app2.processIdentifier
            self.assertTrue(app2.isFinishedLaunching || app2LaunchNotif, "Dummy 2 must be confirmed ready")

            let probeID2 = ExecutionInstanceID(pid: pid2, startTimeSec: 0, startTimeUsec: 0)
            guard let snap2 = collector.currentSnapshot(for: probeID2) else {
                self.assertTrue(false, "Failed to get snapshot for dummy 2")
                return
            }
            let inst2 = snap2.instanceID

            self.assertTrue(inst2 != oldInst, "New execution instance must have different identity")
            print("    [Info] Dummy 2 launched: PID=\(pid2), StartTimeSec=\(inst2.startTimeSec), isFinishedLaunching=\(app2.isFinishedLaunching), launchNotif=\(app2LaunchNotif)")

            let stateMachine = TerminationStateMachine()
            // Old instance state recorded as terminated
            await stateMachine.handleTerminationObserved(instanceID: oldInst)
            let oldIsObserved = await stateMachine.isObservedTerminated(instanceID: oldInst)
            self.assertTrue(oldIsObserved)

            // New instance should start completely clean
            await stateMachine.handleNewExecutionObserved(newInstance: inst2)
            let state2 = await stateMachine.getState(for: inst2)
            self.assertEqual(state2, .idle)
            let newIsObserved = await stateMachine.isObservedTerminated(instanceID: inst2)
            self.assertFalse(newIsObserved)

            // Cleanly terminate dummy 2
            let term2 = DummyAppTerminator(runningApp: app2, expectedBundleURL: bundleDir)
            let protection = MockIntegrationProtectionChecker()
            let dummy2Tracker = NotificationTracker()

            let observer2 = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { notif in
                if let termApp = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   termApp.processIdentifier == pid2,
                   termApp == app2 {
                    let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                    dummy2Tracker.record(pid: termApp.processIdentifier, at: nowNs)
                    Task {
                        await stateMachine.handleTerminationObserved(instanceID: inst2)
                    }
                }
            }

            let initResult2 = await stateMachine.initiateTermination(
                targetInstance: inst2,
                allowedUID: getuid(),
                identityProvider: collector,
                protectionChecker: protection,
                terminator: term2
            )
            print("    [Info] Dummy 2 termination initiated: state=\(initResult2.finalState), terminate() returned=\(term2.lastRequestReturn as Any)")

            let waitDeadline = Date(timeIntervalSinceNow: 5.0)
            while Date() < waitDeadline && !app2.isTerminated {
                self.pumpRunLoop(duration: 0.05)
            }

            // Pump briefly to let async actor state update
            self.pumpRunLoop(duration: 0.1)

            NSWorkspace.shared.notificationCenter.removeObserver(observer2)

            self.assertTrue(app2.isTerminated, "Dummy 2 must be confirmed terminated")
            self.assertTrue(dummy2Tracker.isReceived(for: inst2.pid), "Notification must be received for Dummy 2")
            let finalState2 = await stateMachine.getState(for: inst2)
            switch finalState2 {
            case .confirmed(let src):
                self.assertTrue(true, "Final state for Dummy 2 is confirmed via \(src)")
                print("    [Info] Dummy 2 cleanly terminated: PID=\(pid2), State=.confirmed(\(src))")
            default:
                self.assertTrue(false, "Expected .confirmed, got \(finalState2)")
            }
        }

        let endTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let elapsedMs = Double(endTime - startTime) / 1_000_000.0

        print("\n==================================================")
        print("📊 Integration Test Summary:")
        print("   Assertions Passed: \(passedCount)")
        print("   Assertions Failed: \(failedCount)")
        print("   Elapsed Time: \(String(format: "%.3f", elapsedMs)) ms")
        if failedCount == 0 {
            print("🎉 ALL INTEGRATION TESTS PASSED SUCCESSFULLY!")
        } else {
            print("❌ SOME INTEGRATION TESTS FAILED.")
            exit(1)
        }
        print("==================================================")
    }
}

// MARK: - Integration Test Entry Point

@main
struct IntegrationTestMain {
    @MainActor
    static func main() async {
        let runner = IntegrationTestRunner()
        await runner.runAll()
    }
}
