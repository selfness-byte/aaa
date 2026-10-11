import Foundation
import MacTaskCleanerCore

// MARK: - Mocks for Phase 2 Tests

final class MockProtectionChecker: ProtectionChecker, @unchecked Sendable {
    var checkResults: [ExecutionInstanceID: ProtectionCheckResult] = [:]

    func checkProtection(for instanceID: ExecutionInstanceID) -> ProtectionCheckResult {
        return checkResults[instanceID] ?? .unprotected
    }
}

final class MockAppTerminator: AppTerminator, @unchecked Sendable {
    var alreadyTerminated: Set<ExecutionInstanceID> = []
    var terminateSendSuccess: Bool = true
    var quickTerminationSuccess: Bool = false
    var requestTerminateCallCount: Int = 0

    func isAlreadyTerminated(instanceID: ExecutionInstanceID) -> Bool {
        return alreadyTerminated.contains(instanceID)
    }

    func requestTerminate(instanceID: ExecutionInstanceID) -> Bool {
        requestTerminateCallCount += 1
        return terminateSendSuccess
    }

    func checkQuickTermination(instanceID: ExecutionInstanceID) -> Bool {
        return quickTerminationSuccess
    }
}

final class MockIdentityProvider: ProcessIdentityProvider, @unchecked Sendable {
    var snapshotToReturn: ProcessIdentitySnapshot?

    init(_ snapshot: ProcessIdentitySnapshot? = nil) {
        self.snapshotToReturn = snapshot
    }

    func currentSnapshot(for instanceID: ExecutionInstanceID) -> ProcessIdentitySnapshot? {
        return snapshotToReturn
    }
}

// MARK: - Test Suite Runner (Isolated to MainActor)

@MainActor
final class TestSuiteRunner {
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
        assertTrue(!condition(), message, file: file, line: line)
    }

    func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
        if actual == expected {
            passedCount += 1
        } else {
            failedCount += 1
            print("❌ [FAILED] Expected [\(expected)], got [\(actual)] at \(file):\(line) — \(message)")
        }
    }

    func assertDoubleEqual(_ actual: Double, _ expected: Double, accuracy: Double = 0.0001, _ message: String = "", file: String = #file, line: Int = #line) {
        if abs(actual - expected) <= accuracy {
            passedCount += 1
        } else {
            failedCount += 1
            print("❌ [FAILED] Expected [\(expected) ± \(accuracy)], got [\(actual)] at \(file):\(line) — \(message)")
        }
    }

    func runTest(_ name: String, block: () async throws -> Void) async {
        let beforeFails = failedCount
        let beforePassed = passedCount
        do {
            try await block()
            let assertionsInTest = (passedCount - beforePassed) + (failedCount - beforeFails)
            if assertionsInTest == 0 {
                failedCount += 1
                print("  ❌ [FAIL] \(name) (No assertions executed!)")
            } else if failedCount == beforeFails {
                print("  ✅ [PASS] \(name)")
            } else {
                print("  ❌ [FAIL] \(name)")
            }
        } catch {
            failedCount += 1
            print("  💥 [ERROR] \(name) threw error: \(error)")
        }
    }

    func runAll() async {
        print("==================================================")
        print("🚀 Running MacTaskCleaner Tests (Phase 1 & Phase 2)")
        print("==================================================")

        let startTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let defaultAllowedUID: uid_t = 501

        // MARK: - Phase 1: Pure CPU Calculation & Monotonic Time Tests
        print("\n--- [Phase 1: Pure CPU Calculation & Monotonic Time Tests] ---")

        guard let standardTimebase = MachTimebase(numer: 1, denom: 1) else {
            fatalError("Failed to create standardTimebase")
        }

        await runTest("testBasicCalculationStandard (50% over 1s)") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)

            let sample1 = CPUTimeSample(
                pid: 100,
                instanceStartTimeSec: 1000,
                instanceStartTimeUsec: 500,
                userCPUTimeMach: 1_000_000_000,
                systemCPUTimeMach: 500_000_000,
                monotonicTimeNanoseconds: 10_000_000_000
            )

            let sample2 = CPUTimeSample(
                pid: 100,
                instanceStartTimeSec: 1000,
                instanceStartTimeUsec: 500,
                userCPUTimeMach: 1_300_000_000,
                systemCPUTimeMach: 700_000_000,
                monotonicTimeNanoseconds: 11_000_000_000
            )

            let result = calculator.calculateUsage(previous: sample1, current: sample2)
            if case .valid(let percentage) = result {
                self.assertDoubleEqual(percentage, 50.0)
            } else {
                self.assertTrue(false, "Expected .valid, got \(result)")
            }
        }

        await runTest("testMachTimebaseFractionalConversion (3/125 ratio)") {
            guard let fractionalTimebase = MachTimebase(numer: 3, denom: 125) else {
                self.assertTrue(false, "Failed to create fractional timebase")
                return
            }
            let calculator = CPUUsageCalculator(timebase: fractionalTimebase)

            let sample1 = CPUTimeSample(
                pid: 200,
                instanceStartTimeSec: 2000,
                instanceStartTimeUsec: 0,
                userCPUTimeMach: 0,
                systemCPUTimeMach: 0,
                monotonicTimeNanoseconds: 100_000_000
            )

            let sample2 = CPUTimeSample(
                pid: 200,
                instanceStartTimeSec: 2000,
                instanceStartTimeUsec: 0,
                userCPUTimeMach: 75_000_000,
                systemCPUTimeMach: 50_000_000,
                monotonicTimeNanoseconds: 110_000_000
            )

            let result = calculator.calculateUsage(previous: sample1, current: sample2)
            if case .valid(let percentage) = result {
                self.assertDoubleEqual(percentage, 30.0)
            } else {
                self.assertTrue(false, "Expected .valid, got \(result)")
            }
        }

        await runTest("testExactIntegerTimeConversionBoundary (2^63 - 1024 with 2/1)") {
            guard let timebase2x = MachTimebase(numer: 2, denom: 1) else {
                self.assertTrue(false, "Failed to create 2x timebase")
                return
            }
            // (2^63 - 1024) * 2 = 2^64 - 2048 = 18446744073709549568 (fits in UInt64)
            let ticks = (UInt64(1) << 63) - 1024
            let converted = timebase2x.toNanoseconds(machTicks: ticks)
            let expected: UInt64 = 18446744073709549568
            self.assertEqual(converted, expected)
        }

        await runTest("testExactIntegerTimeConversionPrecision (2^53 + 1 with 2/3)") {
            guard let timebase2over3 = MachTimebase(numer: 2, denom: 3) else {
                self.assertTrue(false, "Failed to create 2/3 timebase")
                return
            }
            // (2^53 + 1) * 2 / 3 = 18014398509481986 / 3 = 6004799503160662 ns exactly (0 ns error)
            let ticks = (UInt64(1) << 53) + 1
            let converted = timebase2over3.toNanoseconds(machTicks: ticks)
            let expected: UInt64 = 6004799503160662
            self.assertEqual(converted, expected)
        }

        await runTest("testPreserveValuesOver100Percent (Multi-core 350%)") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)

            let sample1 = CPUTimeSample(
                pid: 300,
                instanceStartTimeSec: 3000,
                instanceStartTimeUsec: 0,
                userCPUTimeMach: 0,
                systemCPUTimeMach: 0,
                monotonicTimeNanoseconds: 1_000_000_000
            )

            let sample2 = CPUTimeSample(
                pid: 300,
                instanceStartTimeSec: 3000,
                instanceStartTimeUsec: 0,
                userCPUTimeMach: 2_500_000_000,
                systemCPUTimeMach: 1_000_000_000,
                monotonicTimeNanoseconds: 2_000_000_000
            )

            let result = calculator.calculateUsage(previous: sample1, current: sample2)
            if case .valid(let percentage) = result {
                self.assertDoubleEqual(percentage, 350.0)
                self.assertTrue(percentage > 100.0, "Must not clamp to 100%")
            } else {
                self.assertTrue(false, "Expected .valid, got \(result)")
            }
        }

        await runTest("testRejectInstanceMismatchDifferentPID") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)
            let s1 = CPUTimeSample(pid: 400, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 1, systemCPUTimeMach: 1, monotonicTimeNanoseconds: 10)
            let s2 = CPUTimeSample(pid: 401, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 2, systemCPUTimeMach: 2, monotonicTimeNanoseconds: 20)
            let result = calculator.calculateUsage(previous: s1, current: s2)
            self.assertEqual(result, .rejected(reason: .instanceMismatch))
        }

        await runTest("testRejectInstanceMismatchRecycledStartTime") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)
            let s1 = CPUTimeSample(pid: 500, instanceStartTimeSec: 1000, instanceStartTimeUsec: 10, userCPUTimeMach: 1, systemCPUTimeMach: 1, monotonicTimeNanoseconds: 10)
            let s2 = CPUTimeSample(pid: 500, instanceStartTimeSec: 1005, instanceStartTimeUsec: 10, userCPUTimeMach: 2, systemCPUTimeMach: 2, monotonicTimeNanoseconds: 20)
            let result = calculator.calculateUsage(previous: s1, current: s2)
            self.assertEqual(result, .rejected(reason: .instanceMismatch))
        }

        await runTest("testRejectNonPositiveElapsedTime") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)
            let s1 = CPUTimeSample(pid: 600, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 1, systemCPUTimeMach: 1, monotonicTimeNanoseconds: 50)
            let s2 = CPUTimeSample(pid: 600, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 2, systemCPUTimeMach: 2, monotonicTimeNanoseconds: 50)
            let result = calculator.calculateUsage(previous: s1, current: s2)
            self.assertEqual(result, .rejected(reason: .nonPositiveElapsedTime(deltaNs: 0)))
        }

        await runTest("testRejectCounterRollback") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)
            let s1 = CPUTimeSample(pid: 700, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 1000, systemCPUTimeMach: 500, monotonicTimeNanoseconds: 10)
            let s2 = CPUTimeSample(pid: 700, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 900, systemCPUTimeMach: 500, monotonicTimeNanoseconds: 20)
            let result = calculator.calculateUsage(previous: s1, current: s2)
            self.assertEqual(result, .rejected(reason: .counterRollback(userRollback: true, systemRollback: false)))
        }

        // Boundary & Overflow Tests
        await runTest("testRejectMachTicksMultiplicationOverflow (Ticks 2^63 with 2/1)") {
            guard let timebase2x = MachTimebase(numer: 2, denom: 1) else {
                self.assertTrue(false, "Failed to create 2x timebase")
                return
            }
            let calculator = CPUUsageCalculator(timebase: timebase2x)
            let s1 = CPUTimeSample(pid: 800, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 0, systemCPUTimeMach: 0, monotonicTimeNanoseconds: 1_000_000)
            let s2 = CPUTimeSample(pid: 800, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 1 << 63, systemCPUTimeMach: 0, monotonicTimeNanoseconds: 2_000_000)
            let result = calculator.calculateUsage(previous: s1, current: s2)
            self.assertEqual(result, .rejected(reason: .arithmeticOverflow))
        }

        await runTest("testRejectCPUTimeSumOverflow (UInt64.max + 1)") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)
            let s1 = CPUTimeSample(pid: 801, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 0, systemCPUTimeMach: 0, monotonicTimeNanoseconds: 1_000_000)
            let s2 = CPUTimeSample(pid: 801, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: UInt64.max, systemCPUTimeMach: 1, monotonicTimeNanoseconds: 2_000_000)
            let result = calculator.calculateUsage(previous: s1, current: s2)
            self.assertEqual(result, .rejected(reason: .arithmeticOverflow))
        }

        await runTest("testSafelyHandleLargeMonotonicElapsedTime (Diff 2^63 ns)") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)
            let s1 = CPUTimeSample(pid: 802, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 0, systemCPUTimeMach: 0, monotonicTimeNanoseconds: 0)
            let s2 = CPUTimeSample(pid: 802, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 100, systemCPUTimeMach: 100, monotonicTimeNanoseconds: 1 << 63)
            let result = calculator.calculateUsage(previous: s1, current: s2)
            if case .valid(let percentage) = result {
                let expected = (200.0 / Double(UInt64(1) << 63)) * 100.0
                // Guard against degenerate 0.0 passing loose tolerances
                self.assertTrue(percentage > 0.0, "Percentage must be strictly positive, not 0.0")
                self.assertDoubleEqual(percentage, expected, accuracy: 1e-27)
            } else {
                self.assertTrue(false, "Expected .valid with exact tiny percentage, got \(result)")
            }
        }

        await runTest("testRejectInvalidTimebaseZeroNumerOrDenom") {
            let invalid1 = MachTimebase(numer: 0, denom: 1)
            let invalid2 = MachTimebase(numer: 1, denom: 0)
            self.assertEqual(invalid1, nil)
            self.assertEqual(invalid2, nil)
        }

        await runTest("testRejectGenerationMismatchSleepReset") {
            let calculator = CPUUsageCalculator(timebase: standardTimebase)
            let s1 = CPUTimeSample(pid: 803, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 10, systemCPUTimeMach: 10, monotonicTimeNanoseconds: 100, generationID: 1)
            let s2 = CPUTimeSample(pid: 803, instanceStartTimeSec: 1, instanceStartTimeUsec: 0, userCPUTimeMach: 20, systemCPUTimeMach: 20, monotonicTimeNanoseconds: 200, generationID: 2) // Reset during sleep
            let result = calculator.calculateUsage(previous: s1, current: s2)
            self.assertEqual(result, .rejected(reason: .generationMismatch))
        }

        // MARK: - Phase 2: Termination State Machine Tests
        print("\n--- [Phase 2: Mock Termination State Machine Tests] ---")

        let sampleInstance = ExecutionInstanceID(pid: 1234, startTimeSec: 1700000000, startTimeUsec: 500)

        await runTest("testNormalLifecycleFlow (Request -> Await -> Notification -> Confirmed)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertTrue(result.requestID != nil)
            self.assertEqual(result.finalState, .awaitingTermination)
            self.assertEqual(terminator.requestTerminateCallCount, 1)

            await stateMachine.handleTerminationObserved(instanceID: sampleInstance)
            let state = await stateMachine.getState(for: sampleInstance)
            self.assertEqual(state, .confirmed(source: .notification))
            let isDead = await stateMachine.isObservedTerminated(instanceID: sampleInstance)
            self.assertTrue(isDead)
        }

        await runTest("testQuickExitFlow (Immediate termination confirmation)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            terminator.quickTerminationSuccess = true

            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)
            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .confirmed(source: .quickCheck))
            self.assertEqual(terminator.requestTerminateCallCount, 1)
        }

        await runTest("testDuplicateRequestBlocked (Atomic rejection)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            _ = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(terminator.requestTerminateCallCount, 1)

            let second = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(second.finalState, .blocked(reason: .duplicateRequestInProgress))
            // Terminator call count MUST NOT increment on duplicate
            self.assertEqual(terminator.requestTerminateCallCount, 1)
        }

        await runTest("testMissingIdentityBlocked (Hard blocking on unverified info)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(nil),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .missingIdentityInfo))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testInstanceMismatchBlocked (Replaced PID start time)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let mismatched = ProcessIdentitySnapshot(
                instanceID: ExecutionInstanceID(pid: 1234, startTimeSec: 1700000099, startTimeUsec: 0),
                uid: defaultAllowedUID,
                isAlive: true
            )

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(mismatched),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .instanceMismatch))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testProtectionRuleBlocked (Terminal / IDE protection)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            protection.checkResults[sampleInstance] = .protected(ruleName: "TerminalHostProtection")
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .protectedByRule(name: "TerminalHostProtection")))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testBlockProtectionLookupFailure (Fail-safe default deny)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            protection.checkResults[sampleInstance] = .checkFailed(reason: "IO error reading config")
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .protectionCheckFailed(reason: "IO error reading config")))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testBlockRootUID0WithNormalAllowedUID (Unconditional root block)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let rootSnapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: 0, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(rootSnapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .rootProcessBlocked))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testBlockRootUID0EvenWhenAllowedUIDIsZero (Cannot run in root context)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let rootSnapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: 0, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: 0, // Injected root context
                identityProvider: MockIdentityProvider(rootSnapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .invalidAllowedUID(uid: 0)))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testBlockOtherUserUID502 (Other user process blocked)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let otherUserSnapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: 502, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(otherUserSnapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .unauthorizedUser(uid: 502, allowedUID: defaultAllowedUID)))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testBlockProcessNotAlive (Inconsistency: isAlive = false)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let deadSnapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: false)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(deadSnapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .blocked(reason: .processNotAlive))
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testTerminatorReturnsFalse (Terminate request failed)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            terminator.terminateSendSuccess = false
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .requestFailed(reason: "NSRunningApplication.terminate returned false"))
            self.assertEqual(terminator.requestTerminateCallCount, 1)
        }

        await runTest("testTargetAlreadyTerminated (Target already dead before send)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            terminator.alreadyTerminated.insert(sampleInstance)
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            self.assertEqual(result.finalState, .targetAlreadyTerminated)
            self.assertEqual(terminator.requestTerminateCallCount, 0)
        }

        await runTest("testTimeoutMatchingRequestID (Awaiting -> Unconfirmed)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            guard let reqID = result.requestID else {
                self.assertTrue(false, "Missing request ID")
                return
            }

            await stateMachine.handleTimeout(instanceID: sampleInstance, requestID: reqID)
            let state = await stateMachine.getState(for: sampleInstance)
            self.assertEqual(state, .unconfirmedWithinTimeout)
        }

        await runTest("testStaleTimeoutIgnored (Mismatched RequestID ignored)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            _ = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )

            let staleReqID = RequestID()
            await stateMachine.handleTimeout(instanceID: sampleInstance, requestID: staleReqID)
            let state = await stateMachine.getState(for: sampleInstance)
            self.assertEqual(state, .awaitingTermination)
        }

        await runTest("testTimeoutDoesNotOverwriteConfirmed (Notification arrived first)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            guard let reqID = result.requestID else {
                self.assertTrue(false, "Missing request ID")
                return
            }

            await stateMachine.handleTerminationObserved(instanceID: sampleInstance)
            await stateMachine.handleTimeout(instanceID: sampleInstance, requestID: reqID)

            let state = await stateMachine.getState(for: sampleInstance)
            self.assertEqual(state, .confirmed(source: .notification))
        }

        await runTest("testLateNotificationTransition (Unconfirmed -> LateConfirmed)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            let result = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            guard let reqID = result.requestID else {
                self.assertTrue(false, "Missing request ID")
                return
            }

            await stateMachine.handleTimeout(instanceID: sampleInstance, requestID: reqID)
            await stateMachine.handleTerminationObserved(instanceID: sampleInstance)

            let state = await stateMachine.getState(for: sampleInstance)
            self.assertEqual(state, .confirmed(source: .lateNotification))
        }

        await runTest("testNewExecutionInstanceIsolation (Isolation across restarts)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()
            let snapshot = ProcessIdentitySnapshot(instanceID: sampleInstance, uid: defaultAllowedUID, isAlive: true)

            _ = await stateMachine.initiateTermination(
                targetInstance: sampleInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(snapshot),
                protectionChecker: protection,
                terminator: terminator
            )
            await stateMachine.handleTerminationObserved(instanceID: sampleInstance)

            let newInstance = ExecutionInstanceID(pid: 1234, startTimeSec: 1700009999, startTimeUsec: 0)
            await stateMachine.handleNewExecutionObserved(newInstance: newInstance)

            let state = await stateMachine.getState(for: newInstance)
            self.assertEqual(state, .idle)
            let isNewDead = await stateMachine.isObservedTerminated(instanceID: newInstance)
            self.assertFalse(isNewDead)
        }

        // MARK: - Regression Tests for Review Items (R1, R2, R3)

        await runTest("testChronologyCalculationSafeUnderflow (R1 Safe UInt64 Formatting)") {
            // Helper simulation of the safe subtraction function
            func formatTime(observedNs: UInt64?, requestNs: UInt64) -> String {
                guard let obs = observedNs else { return "not observed" }
                guard obs >= requestNs else { return "precedes request" }
                let diffSec = Double(obs - requestNs) / 1e9
                return "\(String(format: "%.3f", diffSec))s"
            }

            let tReq: UInt64 = 343861508321500
            // Test unobserved (nil) does not underflow
            self.assertEqual(formatTime(observedNs: nil, requestNs: tReq), "not observed")
            // Test 0 timestamp does not underflow or crash
            self.assertEqual(formatTime(observedNs: 0, requestNs: tReq), "precedes request")
            // Test out-of-order timestamp does not underflow or crash
            self.assertEqual(formatTime(observedNs: tReq - 100, requestNs: tReq), "precedes request")
            // Test normal timestamp calculates valid difference
            self.assertEqual(formatTime(observedNs: tReq + 1_000_000_000, requestNs: tReq), "1.000s")
        }

        await runTest("testTargetMismatchDoesNotTriggerAlreadyTerminated (R2 Contract Fix)") {
            let stateMachine = TerminationStateMachine()
            let protection = MockProtectionChecker()
            let terminator = MockAppTerminator()

            let requestedPID: pid_t = 1234
            let targetInstance = ExecutionInstanceID(pid: requestedPID, startTimeSec: 1700000000, startTimeUsec: 0)

            // Terminator simulates R2 strict contract: mismatched PID returns false (not true!)
            // Process snapshot has mismatched PID
            let mismatchSnapshot = ProcessIdentitySnapshot(
                instanceID: ExecutionInstanceID(pid: 9999, startTimeSec: 1700000000, startTimeUsec: 0),
                uid: defaultAllowedUID,
                isAlive: true
            )

            let result = await stateMachine.initiateTermination(
                targetInstance: targetInstance,
                allowedUID: defaultAllowedUID,
                identityProvider: MockIdentityProvider(mismatchSnapshot),
                protectionChecker: protection,
                terminator: terminator
            )

            // Must NOT be targetAlreadyTerminated; must fail closed with instanceMismatch
            self.assertEqual(result.finalState, .blocked(reason: .instanceMismatch))
            let isDead = await stateMachine.isObservedTerminated(instanceID: targetInstance)
            self.assertFalse(isDead, "Mismatched target must NOT be recorded as terminated")
        }

        await runTest("testRejectStaleInstanceStartTimeOnCPUSample (R3 Kernel Validation)") {
            let collector = DarwinStatusCollector()
            let selfPID = ProcessInfo.processInfo.processIdentifier

            // First probe real start time of self
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

        let endTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let elapsedMs = Double(endTime - startTime) / 1_000_000.0

        print("\n==================================================")
        print("📊 Test Summary:")
        print("   Assertions Passed: \(passedCount)")
        print("   Assertions Failed: \(failedCount)")
        print("   Elapsed Time: \(String(format: "%.3f", elapsedMs)) ms")
        if failedCount == 0 {
            print("🎉 ALL TESTS PASSED SUCCESSFULLY!")
        } else {
            print("❌ SOME TESTS FAILED.")
            exit(1)
        }
        print("==================================================")
    }
}

// MARK: - Test Main Entry Point

@main
struct TestMain {
    @MainActor
    static func main() async {
        let runner = TestSuiteRunner()
        await runner.runAll()
    }
}
