import Foundation

/// Uniquely identifies an OS-level execution instance using PID and microsecond-level start time.
public struct ExecutionInstanceID: Hashable, Sendable {
    public let pid: pid_t
    public let startTimeSec: UInt64
    public let startTimeUsec: UInt64

    public init(pid: pid_t, startTimeSec: UInt64, startTimeUsec: UInt64) {
        self.pid = pid
        self.startTimeSec = startTimeSec
        self.startTimeUsec = startTimeUsec
    }
}

/// Unique request identifier for internal request-response correlation.
public struct RequestID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Reason why a termination request was blocked from being dispatched.
public enum BlockReason: Sendable, Equatable {
    case duplicateRequestInProgress
    case missingIdentityInfo
    case processNotAlive
    case instanceMismatch
    case invalidAllowedUID(uid: uid_t)
    case rootProcessBlocked
    case unauthorizedUser(uid: uid_t, allowedUID: uid_t)
    case protectedByRule(name: String)
    case protectionCheckFailed(reason: String)
}

/// Source of termination confirmation.
public enum ConfirmationSource: Sendable, Equatable {
    case quickCheck
    case notification
    case lateNotification
}

/// State of a termination request.
public enum TerminationState: Sendable, Equatable {
    case idle
    case blocked(reason: BlockReason)
    case targetAlreadyTerminated
    case requesting
    case awaitingTermination
    case requestFailed(reason: String)
    case unconfirmedWithinTimeout
    case confirmed(source: ConfirmationSource)
}

/// Snapshot of process identity from kernel inspection.
public struct ProcessIdentitySnapshot: Sendable, Equatable {
    public let instanceID: ExecutionInstanceID
    public let uid: uid_t
    public let isAlive: Bool

    public init(instanceID: ExecutionInstanceID, uid: uid_t, isAlive: Bool) {
        self.instanceID = instanceID
        self.uid = uid
        self.isAlive = isAlive
    }
}

/// Result of querying protection rules.
public enum ProtectionCheckResult: Sendable, Equatable {
    case protected(ruleName: String)
    case unprotected
    case checkFailed(reason: String)
}

/// Protocol for inspecting kernel process identity.
public protocol ProcessIdentityProvider: Sendable {
    func currentSnapshot(for instanceID: ExecutionInstanceID) -> ProcessIdentitySnapshot?
}

/// Protocol for checking protection rules.
public protocol ProtectionChecker: Sendable {
    func checkProtection(for instanceID: ExecutionInstanceID) -> ProtectionCheckResult
}

/// Mockable interface for requesting termination on a target app.
public protocol AppTerminator: Sendable {
    func isAlreadyTerminated(instanceID: ExecutionInstanceID) -> Bool
    func requestTerminate(instanceID: ExecutionInstanceID) -> Bool
    func checkQuickTermination(instanceID: ExecutionInstanceID) -> Bool
}

/// Result of initiating a termination request.
public struct InitiationResult: Sendable, Equatable {
    public let requestID: RequestID?
    public let finalState: TerminationState
}

/// State machine managing termination requests with strict serialization and event correlation.
public actor TerminationStateMachine {
    /// Active request per execution instance.
    private var activeRequests: [ExecutionInstanceID: (requestID: RequestID, state: TerminationState)] = [:]

    /// Observed process death facts (decoupled from individual request causality).
    private var observedTerminations: Set<ExecutionInstanceID> = []

    public init() {}

    /// Gets current state for an execution instance.
    public func getState(for instanceID: ExecutionInstanceID) -> TerminationState {
        return activeRequests[instanceID]?.state ?? .idle
    }

    /// Checks if a process execution was observed as terminated.
    public func isObservedTerminated(instanceID: ExecutionInstanceID) -> Bool {
        return observedTerminations.contains(instanceID)
    }

    /// Initiates a termination request following the strict serialized protocol:
    /// 1. Synchronously checks duplicates and registers "processing".
    /// 2. Performs pre-flight verification:
    ///    - allowedUID must be non-zero (cannot execute under root context)
    ///    - target cannot be root (UID 0 is unconditionally blocked)
    ///    - target UID must match allowedUID
    ///    - target must be confirmed alive
    ///    - target instance ID must match exactly
    ///    - protection store must confirm unprotected (fails closed on lookup error)
    /// 3. Transitions to "requesting" and invokes terminator ONLY if all checks pass.
    /// 4. Handles immediate results (failed, quick confirmed, or awaiting).
    public func initiateTermination(
        targetInstance: ExecutionInstanceID,
        allowedUID: uid_t,
        identityProvider: ProcessIdentityProvider,
        protectionChecker: ProtectionChecker,
        terminator: AppTerminator
    ) -> InitiationResult {
        // Step 1: Duplicate check & in-progress registration (Atomic within actor synchronous block)
        if let current = activeRequests[targetInstance] {
            switch current.state {
            case .requesting, .awaitingTermination:
                return InitiationResult(requestID: current.requestID, finalState: .blocked(reason: .duplicateRequestInProgress))
            case .confirmed:
                return InitiationResult(requestID: current.requestID, finalState: current.state)
            case .idle, .blocked, .targetAlreadyTerminated, .requestFailed, .unconfirmedWithinTimeout:
                break // Allow new request attempt
            }
        }

        let newRequestID = RequestID()
        activeRequests[targetInstance] = (requestID: newRequestID, state: .requesting)

        // Step 2: Context safety - the operating context itself cannot be root (UID 0)
        guard allowedUID != 0 else {
            let state: TerminationState = .blocked(reason: .invalidAllowedUID(uid: allowedUID))
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // Step 3: Check if target is already known to be terminated before sending
        if terminator.isAlreadyTerminated(instanceID: targetInstance) || observedTerminations.contains(targetInstance) {
            observedTerminations.insert(targetInstance)
            activeRequests[targetInstance] = (requestID: newRequestID, state: .targetAlreadyTerminated)
            return InitiationResult(requestID: newRequestID, finalState: .targetAlreadyTerminated)
        }

        // Step 4: Final Pre-flight verification (kernel identity snapshot)
        guard let snapshot = identityProvider.currentSnapshot(for: targetInstance) else {
            let state: TerminationState = .blocked(reason: .missingIdentityInfo)
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // 4a. Process must be reported alive by kernel inspection
        guard snapshot.isAlive else {
            let state: TerminationState = .blocked(reason: .processNotAlive)
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // 4b. Exact execution instance match
        guard snapshot.instanceID == targetInstance else {
            let state: TerminationState = .blocked(reason: .instanceMismatch)
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // 4c. UNCONDITIONAL ROOT BLOCK: System processes (UID 0) are blocked regardless of allowedUID
        guard snapshot.uid != 0 else {
            let state: TerminationState = .blocked(reason: .rootProcessBlocked)
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // 4d. Mandatory user isolation: Target UID must match the allowed user UID
        guard snapshot.uid == allowedUID else {
            let state: TerminationState = .blocked(reason: .unauthorizedUser(uid: snapshot.uid, allowedUID: allowedUID))
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // Step 5: Check protection rules (with explicit failure handling)
        switch protectionChecker.checkProtection(for: targetInstance) {
        case .protected(let ruleName):
            let state: TerminationState = .blocked(reason: .protectedByRule(name: ruleName))
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        case .checkFailed(let reason):
            // Fail-safe: Default deny if protection rules cannot be queried
            let state: TerminationState = .blocked(reason: .protectionCheckFailed(reason: reason))
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        case .unprotected:
            break // Proceed to termination
        }

        // Step 6: Issue termination request ONLY after all checks passed
        let sendSuccess = terminator.requestTerminate(instanceID: targetInstance)
        guard sendSuccess else {
            let state: TerminationState = .requestFailed(reason: "NSRunningApplication.terminate returned false")
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // Step 7: Quick check immediately after request
        if terminator.checkQuickTermination(instanceID: targetInstance) {
            observedTerminations.insert(targetInstance)
            let state: TerminationState = .confirmed(source: .quickCheck)
            activeRequests[targetInstance] = (requestID: newRequestID, state: state)
            return InitiationResult(requestID: newRequestID, finalState: state)
        }

        // Step 8: Transition to awaiting observation
        let state: TerminationState = .awaitingTermination
        activeRequests[targetInstance] = (requestID: newRequestID, state: state)
        return InitiationResult(requestID: newRequestID, finalState: state)
    }

    /// Handles timeout for a specific (ExecutionInstanceID, RequestID) pair.
    public func handleTimeout(instanceID: ExecutionInstanceID, requestID: RequestID) {
        guard let active = activeRequests[instanceID] else { return }

        // Validate correlation ID: only the matching request can trigger timeout
        guard active.requestID == requestID else { return }

        // If already confirmed (e.g. notification arrived before timeout handler executed), do not overwrite!
        if case .confirmed = active.state {
            return
        }

        // Transition from awaitingTermination to unconfirmedWithinTimeout
        if active.state == .awaitingTermination {
            activeRequests[instanceID] = (requestID: requestID, state: .unconfirmedWithinTimeout)
        }
    }

    /// Handles system termination observation (e.g. from NSWorkspace notification).
    public func handleTerminationObserved(instanceID: ExecutionInstanceID) {
        // Record the physical death fact independently
        observedTerminations.insert(instanceID)

        guard let active = activeRequests[instanceID] else { return }

        switch active.state {
        case .awaitingTermination, .requesting:
            // Normal in-time confirmation
            activeRequests[instanceID] = (requestID: active.requestID, state: .confirmed(source: .notification))
        case .unconfirmedWithinTimeout:
            // Late termination: "종료 확인 — 제한 시간 이후"
            activeRequests[instanceID] = (requestID: active.requestID, state: .confirmed(source: .lateNotification))
        case .confirmed, .idle, .blocked, .targetAlreadyTerminated, .requestFailed:
            // Already confirmed or terminal, keep state idempotent
            break
        }
    }

    /// Handles observation of a new execution instance with same PID but new start time.
    /// Ensures old requests never taint the new execution instance.
    public func handleNewExecutionObserved(newInstance: ExecutionInstanceID) {
        // Must start with clean state
        if activeRequests[newInstance] == nil {
            activeRequests[newInstance] = (requestID: RequestID(), state: .idle)
        }
    }
}
