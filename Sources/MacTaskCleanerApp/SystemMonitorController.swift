import AppKit
import Foundation
import MacTaskCleanerCore

/// Category filter for process list in UI
public enum AppFilterCategory: String, CaseIterable {
    case all = "전체 앱"
    case safeCandidates = "정리 가능"
    case protectedOnly = "보호 대상"
}

/// Representation of an active user-facing process
public struct AppProcessItem: Identifiable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let bundleID: String
    public let bundlePath: String
    public let icon: NSImage?
    public let memoryBytes: UInt64
    public let memoryFormatted: String
    public let instanceID: ExecutionInstanceID
    public let protection: ProtectionCheckResult
    public var isTerminating: Bool

    public var isSafeCandidate: Bool {
        if case .unprotected = protection {
            return true
        }
        return false
    }

    public var protectionBadgeText: String {
        switch protection {
        case .protected(let rule):
            return "🔒 \(rule)"
        case .unprotected:
            return "🟢 정리 가능"
        case .checkFailed(let reason):
            return "⚠️ 확인 불가 (\(reason))"
        }
    }
}

/// Chronology audit record for termination actions
public struct ChronologyLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let appName: String
    public let pid: pid_t
    public let requestTimeNs: UInt64
    public let returnTimeNs: UInt64
    public let terminateResult: Bool
    public let finalState: String
    public let latencyDescription: String
}

/// Controller coordinating system resource polling and safe termination lifecycle
@MainActor
public final class SystemMonitorController: NSObject {
    public static let shared = SystemMonitorController()

    public private(set) var totalRAMBytes: UInt64 = 8 * 1024 * 1024 * 1024
    public private(set) var wiredBytes: UInt64 = 0
    public private(set) var activeBytes: UInt64 = 0
    public private(set) var compressedBytes: UInt64 = 0
    public private(set) var freeBytes: UInt64 = 0

    public private(set) var swapTotalBytes: UInt64 = 0
    public private(set) var swapUsedBytes: UInt64 = 0
    public private(set) var swapAvailBytes: UInt64 = 0

    public private(set) var memoryPressureLevel: Int32 = 1

    public private(set) var runningApps: [AppProcessItem] = []
    public private(set) var chronologyLogs: [ChronologyLogEntry] = []
    public private(set) var lastAuditMessage: String = "시스템 관측 대기 중"
    public private(set) var isTerminatingInProgress: Bool = false

    public var onUpdate: (() -> Void)?

    private let collector = DarwinStatusCollector()
    private let protectionChecker = DefaultProtectionChecker()
    private let stateMachine = TerminationStateMachine()
    private let notificationTracker = NotificationTracker()

    private var refreshTimer: Timer?
    private var notificationObserver: (any NSObjectProtocol)?

    public override init() {
        super.init()
        self.totalRAMBytes = collector.queryPhysicalRAM()
        setupNotificationObserver()
        refresh()
        startTimer(interval: 2.0)
    }

    isolated deinit {
        if let obs = notificationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        refreshTimer?.invalidate()
    }

    private func setupNotificationObserver() {
        notificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self else { return }
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            let nowNs = self.collector.currentMonotonicNanoseconds()
            self.notificationTracker.record(pid: pid, at: nowNs)
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    public func startTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    public func refresh() {
        // 1. Memory metrics
        if let metrics = collector.collectSystemMemoryMetrics() {
            self.wiredBytes = metrics.wiredBytes
            self.activeBytes = metrics.activeBytes
            self.compressedBytes = metrics.compressedBytes
            self.freeBytes = metrics.freeExcludingSpeculativeBytes
            self.swapTotalBytes = metrics.swapTotalBytes
            self.swapUsedBytes = metrics.swapUsedBytes
            self.swapAvailBytes = metrics.swapAvailBytes
        }
        self.totalRAMBytes = collector.queryPhysicalRAM()
        self.memoryPressureLevel = collector.queryMemoryPressureLevel()

        // 2. Running apps inspection
        let currentApps = NSWorkspace.shared.runningApplications
        var items: [AppProcessItem] = []

        for app in currentApps {
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            guard pid > 0 else { continue }

            let name = app.localizedName ?? "이름 없음"
            let bundleID = app.bundleIdentifier ?? "알 수 없음"
            let bundlePath = app.bundleURL?.path ?? "경로 없음"
            let icon = app.icon

            let memBytes = collector.queryProcessMemory(for: pid) ?? 0
            let memFormatted = formatBytes(memBytes)

            let dummyInstance = ExecutionInstanceID(pid: pid, startTimeSec: 0, startTimeUsec: 0)
            let snapshot = collector.currentSnapshot(for: dummyInstance)
            let instanceID = snapshot?.instanceID ?? dummyInstance

            let protection = protectionChecker.checkProtection(for: instanceID)

            items.append(AppProcessItem(
                pid: pid,
                name: name,
                bundleID: bundleID,
                bundlePath: bundlePath,
                icon: icon,
                memoryBytes: memBytes,
                memoryFormatted: memFormatted,
                instanceID: instanceID,
                protection: protection,
                isTerminating: false
            ))
        }

        // Sort: safe candidates first, then by memory descending
        items.sort { a, b in
            if a.isSafeCandidate != b.isSafeCandidate {
                return a.isSafeCandidate && !b.isSafeCandidate
            }
            return a.memoryBytes > b.memoryBytes
        }

        self.runningApps = items
        self.onUpdate?()
    }

    public var menuBarTitle: String {
        let usedRAM = wiredBytes + activeBytes + compressedBytes
        let usedRAMGB = Double(usedRAM) / (1024 * 1024 * 1024)
        let swapUsedMB = Double(swapUsedBytes) / (1024 * 1024)

        let pressureIcon: String
        switch memoryPressureLevel {
        case 1: pressureIcon = "🟢"
        case 2: pressureIcon = "🟡"
        default: pressureIcon = "🔴"
        }

        if swapUsedBytes > 1024 * 1024 * 200 {
            return String(format: "%@ RAM %.1fG | Swap %.0fM", pressureIcon, usedRAMGB, swapUsedMB)
        } else {
            return String(format: "%@ RAM %.1fG", pressureIcon, usedRAMGB)
        }
    }

    /// Safe termination request via state machine
    public func requestSafeTermination(for item: AppProcessItem, completion: (@Sendable (Bool, String) -> Void)? = nil) {
        guard let runningApp = NSRunningApplication(processIdentifier: item.pid),
              !runningApp.isTerminated else {
            self.lastAuditMessage = "PID \(item.pid)(\(item.name))은 이미 종료되었습니다."
            self.refresh()
            completion?(true, "이미 종료됨")
            return
        }

        self.isTerminatingInProgress = true
        self.lastAuditMessage = "PID \(item.pid)(\(item.name)) 일반 종료 요청 시작..."

        Task {
            let tReq = collector.currentMonotonicNanoseconds()
            let terminator = NSWorkspaceAppTerminator(runningApp: runningApp)

            let initResult = await stateMachine.initiateTermination(
                targetInstance: item.instanceID,
                allowedUID: getuid(),
                identityProvider: collector,
                protectionChecker: protectionChecker,
                terminator: terminator
            )

            let tRet = collector.currentMonotonicNanoseconds()
            let reqReturn = (initResult.requestID != nil)

            var finalStateDesc = ""
            var latencyDesc = ""

            switch initResult.finalState {
            case .idle, .requesting:
                finalStateDesc = "대기"
                latencyDesc = "0.0s"

            case .blocked(let reason):
                finalStateDesc = "차단됨: \(reason)"
                latencyDesc = "0.0s (차단)"
                self.lastAuditMessage = "⚠️ [안전 차단] \(item.name): \(reason)"

            case .targetAlreadyTerminated:
                finalStateDesc = "이미 종료됨"
                latencyDesc = ChronologyFormatter.format(observedNs: tRet, requestNs: tReq)
                self.lastAuditMessage = "ℹ️ \(item.name)은 이미 종료된 상태입니다."

            case .requestFailed(let reason):
                finalStateDesc = "요청 실패: \(reason)"
                latencyDesc = "0.0s"
                self.lastAuditMessage = "❌ \(item.name) 요청 실패: \(reason)"

            case .awaitingTermination:
                self.lastAuditMessage = "⏳ \(item.name) 종료 대기 중 (최대 3초)..."
                var observedTerminated = false
                let waitLimitNs = tReq + 3_000_000_000

                while collector.currentMonotonicNanoseconds() < waitLimitNs {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if runningApp.isTerminated {
                        observedTerminated = true
                        break
                    }
                }

                let tObserved = collector.currentMonotonicNanoseconds()

                if observedTerminated {
                    await stateMachine.handleTerminationObserved(instanceID: item.instanceID)
                    finalStateDesc = "정상 종료 완료"
                    latencyDesc = ChronologyFormatter.format(observedNs: tObserved, requestNs: tReq)
                    self.lastAuditMessage = "✅ \(item.name) 정상 종료 완료 (\(latencyDesc))"
                } else {
                    if let reqID = initResult.requestID {
                        await stateMachine.handleTimeout(instanceID: item.instanceID, requestID: reqID)
                    }
                    finalStateDesc = "제한 시간 초과 (강제 종료하지 않음)"
                    latencyDesc = "3.0s+ (미확인)"
                    self.lastAuditMessage = "ℹ️ \(item.name) 종료 대기 시간 초과 (SIGKILL 배제)"
                }

            case .confirmed(let source):
                finalStateDesc = "확인됨 (\(source))"
                latencyDesc = ChronologyFormatter.format(observedNs: tRet, requestNs: tReq)
                self.lastAuditMessage = "✅ \(item.name) 종료 확인 완료 (\(latencyDesc))"

            case .unconfirmedWithinTimeout:
                finalStateDesc = "타임아웃 (강제 종료 배제)"
                latencyDesc = "3.0s+"
            }

            let entry = ChronologyLogEntry(
                timestamp: Date(),
                appName: item.name,
                pid: item.pid,
                requestTimeNs: tReq,
                returnTimeNs: tRet,
                terminateResult: reqReturn,
                finalState: finalStateDesc,
                latencyDescription: latencyDesc
            )

            self.chronologyLogs.insert(entry, at: 0)
            if self.chronologyLogs.count > 30 {
                self.chronologyLogs.removeLast()
            }

            self.isTerminatingInProgress = false
            self.refresh()
            completion?(reqReturn, finalStateDesc)
        }
    }

    public func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0

        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
}
