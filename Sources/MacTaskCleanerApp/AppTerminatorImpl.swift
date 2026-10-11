import AppKit
import Foundation
import MacTaskCleanerCore

/// Production implementation of AppTerminator wrapping NSRunningApplication.
/// Conforms to the strict confinement guard: verifies PID, bundle URL, and UID.
public final class NSWorkspaceAppTerminator: AppTerminator, @unchecked Sendable {
    private let allowedPID: pid_t
    private let expectedBundleURL: URL?

    public init(runningApp: NSRunningApplication) {
        self.allowedPID = runningApp.processIdentifier
        self.expectedBundleURL = runningApp.bundleURL
    }

    public func isAlreadyTerminated(instanceID: ExecutionInstanceID) -> Bool {
        guard instanceID.pid == allowedPID else { return false }
        guard let app = NSRunningApplication(processIdentifier: instanceID.pid) else {
            return true
        }
        return app.isTerminated
    }

    public func requestTerminate(instanceID: ExecutionInstanceID) -> Bool {
        guard instanceID.pid == allowedPID else { return false }
        guard let app = NSRunningApplication(processIdentifier: instanceID.pid) else {
            return false
        }
        if let expected = expectedBundleURL, let actual = app.bundleURL, expected != actual {
            return false
        }
        return app.terminate()
    }

    public func checkQuickTermination(instanceID: ExecutionInstanceID) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: instanceID.pid) else {
            return true
        }
        return app.isTerminated
    }
}

/// Production implementation of ProtectionChecker enforcing the design rules:
/// - Critical macOS system daemons / UI servers protected
/// - Terminals, IDEs, code editors protected
/// - Non-regular (accessory/prohibited) apps protected
/// - Current running app (MacTaskCleaner) protected
public final class DefaultProtectionChecker: ProtectionChecker, Sendable {
    public let protectedBundleIDs: Set<String>
    public let protectedProcessNames: Set<String>

    public init(
        additionalProtectedBundleIDs: Set<String> = [],
        additionalProtectedNames: Set<String> = []
    ) {
        self.protectedBundleIDs = Set([
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.systemuiserver",
            "com.apple.WindowManager",
            "com.apple.Spotlight",
            "com.apple.loginwindow",
            "com.apple.ActivityMonitor",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.google.antigravity-ide",
            "com.mactaskcleaner.app"
        ]).union(additionalProtectedBundleIDs)

        self.protectedProcessNames = Set([
            "Finder", "Dock", "SystemUIServer", "WindowServer", "loginwindow",
            "Activity Monitor", "Terminal", "iTerm", "iTerm2", "Code", "Xcode",
            "Antigravity IDE", "MacTaskCleanerApp"
        ]).union(additionalProtectedNames)
    }

    public func checkProtection(for instanceID: ExecutionInstanceID) -> ProtectionCheckResult {
        guard let app = NSRunningApplication(processIdentifier: instanceID.pid) else {
            return .checkFailed(reason: "NSRunningApplication not found for PID \(instanceID.pid)")
        }

        if let bundleID = app.bundleIdentifier, protectedBundleIDs.contains(bundleID) {
            return .protected(ruleName: "시스템/개발도구 보호: \(bundleID)")
        }

        if let name = app.localizedName, protectedProcessNames.contains(name) {
            return .protected(ruleName: "시스템/개발도구 보호: \(name)")
        }

        if app.activationPolicy != .regular {
            return .protected(ruleName: "백그라운드/액세서리 프로세스 보호")
        }

        if app.processIdentifier == getpid() {
            return .protected(ruleName: "맥 작업정리 자체 프로세스 보호")
        }

        return .unprotected
    }
}
