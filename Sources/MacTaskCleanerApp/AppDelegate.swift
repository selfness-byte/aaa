import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app (lives in menu bar without taking space in Dock)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupMenu()

        // Bind update from controller
        SystemMonitorController.shared.onUpdate = { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatusItemTitle()
            }
        }
        updateStatusItemTitle()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "RAM 관측 중..."
            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        }
    }

    private func setupMenu() {
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
    }

    private func updateStatusItemTitle() {
        if let button = statusItem.button {
            button.title = SystemMonitorController.shared.menuBarTitle
        }
    }

    // MARK: - NSMenuDelegate (Dynamically construct menu on click)
    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        let ctrl = SystemMonitorController.shared

        // 1. App Title
        let titleItem = NSMenuItem(title: "맥 작업정리 v1 (M1 8GB)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        statusMenu.addItem(titleItem)

        // 2. RAM & Swap Info
        let totalGB = Double(ctrl.totalRAMBytes) / (1024 * 1024 * 1024)
        let usedBytes = ctrl.wiredBytes + ctrl.activeBytes + ctrl.compressedBytes
        let usedGB = Double(usedBytes) / (1024 * 1024 * 1024)
        let ramItem = NSMenuItem(
            title: String(format: "  • 물리 RAM: %.2fG / %.1fG", usedGB, totalGB),
            action: nil,
            keyEquivalent: ""
        )
        ramItem.isEnabled = false
        statusMenu.addItem(ramItem)

        let swapUsedMB = Double(ctrl.swapUsedBytes) / (1024 * 1024)
        let swapTotalMB = Double(ctrl.swapTotalBytes) / (1024 * 1024)
        let swapItem = NSMenuItem(
            title: String(format: "  • 스왑 사용: %.0fM / %.0fM", swapUsedMB, swapTotalMB),
            action: nil,
            keyEquivalent: ""
        )
        swapItem.isEnabled = false
        statusMenu.addItem(swapItem)

        let pressureDesc: String
        switch ctrl.memoryPressureLevel {
        case 1: pressureDesc = "🟢 정상"
        case 2: pressureDesc = "🟡 주의 (압박 발생)"
        default: pressureDesc = "🔴 위험 (심각)"
        }
        let pressureItem = NSMenuItem(title: "  • 메모리 압박: \(pressureDesc)", action: nil, keyEquivalent: "")
        pressureItem.isEnabled = false
        statusMenu.addItem(pressureItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 3. Top Process Candidates Section
        let candidateHeader = NSMenuItem(title: "주요 실행 앱 요약 (상위 5개):", action: nil, keyEquivalent: "")
        candidateHeader.isEnabled = false
        statusMenu.addItem(candidateHeader)

        let topApps = ctrl.runningApps.prefix(5)
        if topApps.isEmpty {
            let emptyItem = NSMenuItem(title: "  (실행 중인 앱 없음)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            statusMenu.addItem(emptyItem)
        } else {
            for (idx, app) in topApps.enumerated() {
                let badge = app.isSafeCandidate ? "▶ [정리]" : "🔒 [보호]"
                let title = "  \(badge) \(app.name) (\(app.memoryFormatted))"
                let item = NSMenuItem(title: title, action: #selector(onMenuAppClicked(_:)), keyEquivalent: "")
                item.target = self
                item.tag = idx
                item.isEnabled = app.isSafeCandidate
                statusMenu.addItem(item)
            }
        }

        statusMenu.addItem(NSMenuItem.separator())

        // 4. Open Detail Window
        let openDetailItem = NSMenuItem(
            title: "🖥️ 상세 관측 및 정리 창 열기...",
            action: #selector(onOpenDetailWindow),
            keyEquivalent: "o"
        )
        openDetailItem.target = self
        statusMenu.addItem(openDetailItem)

        // 5. Refresh
        let refreshItem = NSMenuItem(
            title: "🔄 새로고침",
            action: #selector(onRefresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        statusMenu.addItem(refreshItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 6. Quit
        let quitItem = NSMenuItem(
            title: "❌ 맥 작업정리 종료",
            action: #selector(onQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func onMenuAppClicked(_ sender: NSMenuItem) {
        let idx = sender.tag
        let ctrl = SystemMonitorController.shared
        guard idx < ctrl.runningApps.count else { return }
        let target = ctrl.runningApps[idx]

        // Bring detail window to front and prompt
        DetailWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "안전 종료 요청: \(target.name)"
        alert.informativeText =
            "대상 PID: \(target.pid)\n" +
            "메모리: \(target.memoryFormatted)\n\n" +
            "• 표준 terminate() 신호로 정상 종료를 요청합니다.\n" +
            "• 저장되지 않은 문서가 있다면 앱 자체의 저장 확인 창이 표시됩니다.\n" +
            "• 강제 종료(SIGKILL)는 수행하지 않습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "일반 종료 요청")
        alert.addButton(withTitle: "취소")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            ctrl.requestSafeTermination(for: target)
        }
    }

    @objc private func onOpenDetailWindow() {
        DetailWindowController.shared.showWindow(nil)
        DetailWindowController.shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func onRefresh() {
        SystemMonitorController.shared.refresh()
    }

    @objc private func onQuit() {
        NSApp.terminate(nil)
    }
}
