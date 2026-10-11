import AppKit
import Foundation
import MacTaskCleanerCore

/// Dedicated Native macOS Window Controller for detailed inspection and safe termination
@MainActor
public final class DetailWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let shared = DetailWindowController()

    private var currentFilter: AppFilterCategory = .all
    private var searchQuery: String = ""
    private var displayedApps: [AppProcessItem] = []

    private var memoryLabel: NSTextField!
    private var swapLabel: NSTextField!
    private var pressureBadge: NSTextField!
    private var searchField: NSSearchField!
    private var filterSegment: NSSegmentedControl!
    private var tableView: NSTableView!
    private var auditTextView: NSTextView!
    private var statusLabel: NSTextField!

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 680, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "맥 작업정리 v1 — 시스템 메모리 및 프로세스 관리"
        window.center()
        window.minSize = NSSize(width: 580, height: 480)
        super.init(window: window)

        setupUI()
        bindController()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let padding: CGFloat = 16

        // 1. Header & Memory Info Card
        let headerBox = NSBox(frame: NSRect(x: padding, y: contentView.bounds.height - 110, width: contentView.bounds.width - padding * 2, height: 95))
        headerBox.title = "시스템 자원 관측 (Apple Silicon M1 • 8GB)"
        headerBox.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(headerBox)

        let boxContent = NSView(frame: headerBox.contentView!.bounds)
        boxContent.autoresizingMask = [.width, .height]
        headerBox.contentView = boxContent

        memoryLabel = NSTextField(labelWithString: "물리 메모리(RAM): 조회 중...")
        memoryLabel.frame = NSRect(x: 12, y: 44, width: 420, height: 20)
        memoryLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        boxContent.addSubview(memoryLabel)

        swapLabel = NSTextField(labelWithString: "스왑(Swap): 조회 중...")
        swapLabel.frame = NSRect(x: 12, y: 22, width: 420, height: 18)
        swapLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        swapLabel.textColor = .secondaryLabelColor
        boxContent.addSubview(swapLabel)

        pressureBadge = NSTextField(labelWithString: "🟢 정상")
        pressureBadge.frame = NSRect(x: boxContent.bounds.width - 160, y: 35, width: 140, height: 26)
        pressureBadge.autoresizingMask = [.minXMargin]
        pressureBadge.alignment = .center
        pressureBadge.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        pressureBadge.wantsLayer = true
        pressureBadge.layer?.cornerRadius = 6
        pressureBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        boxContent.addSubview(pressureBadge)

        // 2. Search & Filter Bar
        let filterY = contentView.bounds.height - 150
        searchField = NSSearchField(frame: NSRect(x: padding, y: filterY, width: 260, height: 26))
        searchField.placeholderString = "앱 이름 또는 PID 검색..."
        searchField.target = self
        searchField.action = #selector(onSearchChanged)
        contentView.addSubview(searchField)

        filterSegment = NSSegmentedControl(labels: ["전체 앱", "정리 가능", "보호 대상"], trackingMode: .selectOne, target: self, action: #selector(onFilterChanged))
        filterSegment.selectedSegment = 0
        filterSegment.frame = NSRect(x: 286, y: filterY, width: 230, height: 26)
        contentView.addSubview(filterSegment)

        let refreshBtn = NSButton(title: "새로고침", target: self, action: #selector(onRefreshClicked))
        refreshBtn.frame = NSRect(x: contentView.bounds.width - padding - 85, y: filterY, width: 85, height: 26)
        refreshBtn.autoresizingMask = [.minXMargin]
        contentView.addSubview(refreshBtn)

        // 3. Process Table View
        let tableY: CGFloat = 135
        let tableHeight = filterY - tableY - 10
        let scrollTable = NSScrollView(frame: NSRect(x: padding, y: tableY, width: contentView.bounds.width - padding * 2, height: tableHeight))
        scrollTable.autoresizingMask = [.width, .height]
        scrollTable.hasVerticalScroller = true
        scrollTable.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollTable.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 32
        tableView.delegate = self
        tableView.dataSource = self

        let colApp = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("colApp"))
        colApp.title = "실행 중인 앱"
        colApp.width = 240
        tableView.addTableColumn(colApp)

        let colPID = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("colPID"))
        colPID.title = "PID"
        colPID.width = 60
        tableView.addTableColumn(colPID)

        let colMem = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("colMem"))
        colMem.title = "메모리"
        colMem.width = 95
        tableView.addTableColumn(colMem)

        let colStatus = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("colStatus"))
        colStatus.title = "보호 분류"
        colStatus.width = 130
        tableView.addTableColumn(colStatus)

        let colAction = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("colAction"))
        colAction.title = "작업"
        colAction.width = 85
        tableView.addTableColumn(colAction)

        scrollTable.documentView = tableView
        contentView.addSubview(scrollTable)

        // 4. Audit Log Box
        let auditBox = NSBox(frame: NSRect(x: padding, y: 40, width: contentView.bounds.width - padding * 2, height: 85))
        auditBox.title = "안전 종료 감사 기록 (Chronology)"
        auditBox.autoresizingMask = [.width, .maxYMargin]
        contentView.addSubview(auditBox)

        let scrollLog = NSScrollView(frame: NSRect(x: 8, y: 6, width: auditBox.bounds.width - 20, height: 55))
        scrollLog.autoresizingMask = [.width, .height]
        scrollLog.hasVerticalScroller = true
        scrollLog.borderType = .noBorder

        auditTextView = NSTextView(frame: scrollLog.bounds)
        auditTextView.isEditable = false
        auditTextView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        auditTextView.string = "감사 기록 대기 중..."
        scrollLog.documentView = auditTextView
        auditBox.contentView?.addSubview(scrollLog)

        // 5. Footer status
        statusLabel = NSTextField(labelWithString: "상태: 시스템 관측 정상 동작 중")
        statusLabel.frame = NSRect(x: padding, y: 12, width: contentView.bounds.width - padding * 2, height: 18)
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)
    }

    private func bindController() {
        SystemMonitorController.shared.onUpdate = { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateView()
            }
        }
        updateView()
    }

    private func updateView() {
        let ctrl = SystemMonitorController.shared

        // Memory text
        let totalGB = Double(ctrl.totalRAMBytes) / (1024 * 1024 * 1024)
        let usedBytes = ctrl.wiredBytes + ctrl.activeBytes + ctrl.compressedBytes
        let usedGB = Double(usedBytes) / (1024 * 1024 * 1024)
        let wiredGB = Double(ctrl.wiredBytes) / (1024 * 1024 * 1024)
        let compGB = Double(ctrl.compressedBytes) / (1024 * 1024 * 1024)

        memoryLabel.stringValue = String(
            format: "물리 메모리: %.2f GB / %.1f GB (고정 %.1fG, 압축 %.1fG)",
            usedGB, totalGB, wiredGB, compGB
        )

        let swapUsedMB = Double(ctrl.swapUsedBytes) / (1024 * 1024)
        let swapTotalMB = Double(ctrl.swapTotalBytes) / (1024 * 1024)
        let swapAvailMB = Double(ctrl.swapAvailBytes) / (1024 * 1024)
        swapLabel.stringValue = String(
            format: "스왑: 사용 %.0f MB / 전체 %.0f MB (여유 %.0f MB)",
            swapUsedMB, swapTotalMB, swapAvailMB
        )

        switch ctrl.memoryPressureLevel {
        case 1:
            pressureBadge.stringValue = "🟢 정상"
            pressureBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        case 2:
            pressureBadge.stringValue = "🟡 주의"
            pressureBadge.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
        default:
            pressureBadge.stringValue = "🔴 위험"
            pressureBadge.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        }

        // Filter apps
        filterAndReloadApps()

        // Audit log text
        if !ctrl.chronologyLogs.isEmpty {
            var lines: [String] = []
            for log in ctrl.chronologyLogs.prefix(15) {
                let df = DateFormatter()
                df.dateFormat = "HH:mm:ss"
                let timeStr = df.string(from: log.timestamp)
                lines.append("[\(timeStr)] \(log.appName) (PID \(log.pid)) -> \(log.finalState) (\(log.latencyDescription))")
            }
            auditTextView.string = lines.joined(separator: "\n")
        }

        statusLabel.stringValue = ctrl.lastAuditMessage
    }

    private func filterAndReloadApps() {
        let all = SystemMonitorController.shared.runningApps
        displayedApps = all.filter { item in
            switch currentFilter {
            case .all: break
            case .safeCandidates: if !item.isSafeCandidate { return false }
            case .protectedOnly: if item.isSafeCandidate { return false }
            }

            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                if !item.name.lowercased().contains(q) &&
                   !item.bundleID.lowercased().contains(q) &&
                   !String(item.pid).contains(q) {
                    return false
                }
            }
            return true
        }
        tableView.reloadData()
    }

    @objc private func onSearchChanged() {
        searchQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filterAndReloadApps()
    }

    @objc private func onFilterChanged() {
        switch filterSegment.selectedSegment {
        case 1: currentFilter = .safeCandidates
        case 2: currentFilter = .protectedOnly
        default: currentFilter = .all
        }
        filterAndReloadApps()
    }

    @objc private func onRefreshClicked() {
        SystemMonitorController.shared.refresh()
    }

    // MARK: - NSTableViewDataSource & Delegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return displayedApps.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedApps.count, let column = tableColumn else { return nil }
        let item = displayedApps[row]

        let cellIdentifier = column.identifier
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellIdentifier
            let textField = NSTextField(labelWithString: "")
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.autoresizingMask = [.width, .height]
            textField.frame = NSRect(x: 2, y: 4, width: column.width - 4, height: 22)
            cell?.addSubview(textField)
            cell?.textField = textField
        }

        switch cellIdentifier.rawValue {
        case "colApp":
            cell?.textField?.stringValue = item.name
            if cell?.imageView == nil {
                let imgView = NSImageView(frame: NSRect(x: 2, y: 6, width: 20, height: 20))
                cell?.addSubview(imgView)
                cell?.imageView = imgView
                cell?.textField?.frame = NSRect(x: 26, y: 4, width: column.width - 28, height: 22)
            }
            cell?.imageView?.image = item.icon

        case "colPID":
            cell?.textField?.stringValue = String(item.pid)
            cell?.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        case "colMem":
            cell?.textField?.stringValue = item.memoryFormatted
            cell?.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
            cell?.textField?.alignment = .right

        case "colStatus":
            cell?.textField?.stringValue = item.isSafeCandidate ? "🟢 정리 가능" : "🔒 보호됨"
            cell?.textField?.textColor = item.isSafeCandidate ? .systemGreen : .secondaryLabelColor

        case "colAction":
            // Reuse or create action button
            cell?.subviews.forEach { if $0 is NSButton { $0.removeFromSuperview() } }
            cell?.textField?.isHidden = true

            if item.isSafeCandidate {
                let btn = NSButton(title: "정리 요청", target: self, action: #selector(onTerminateButtonClicked(_:)))
                btn.frame = NSRect(x: 4, y: 4, width: 75, height: 22)
                btn.bezelStyle = .rounded
                btn.tag = row
                cell?.addSubview(btn)
            } else {
                let label = NSTextField(labelWithString: "—")
                label.frame = NSRect(x: 4, y: 4, width: 75, height: 22)
                label.alignment = .center
                label.textColor = .tertiaryLabelColor
                cell?.addSubview(label)
            }

        default:
            break
        }

        return cell
    }

    @objc private func onTerminateButtonClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row < displayedApps.count else { return }
        let item = displayedApps[row]

        let alert = NSAlert()
        alert.messageText = "안전 종료 요청: \(item.name)"
        alert.informativeText =
            "대상 PID: \(item.pid)\n" +
            "경로: \(item.bundlePath)\n\n" +
            "• 표준 terminate() 신호로 정상 종료를 요청합니다.\n" +
            "• 저장되지 않은 문서가 있다면 앱 자체의 저장 확인 창이 표시됩니다.\n" +
            "• 시스템 안전 설계 원칙에 따라 강제 종료(SIGKILL)는 수행하지 않습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "일반 종료 요청")
        alert.addButton(withTitle: "취소")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SystemMonitorController.shared.requestSafeTermination(for: item)
        }
    }
}
