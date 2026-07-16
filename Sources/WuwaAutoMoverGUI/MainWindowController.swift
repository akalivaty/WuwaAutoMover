import Cocoa
import WuwaAutoMoverCore

private struct StatusCheckOutput: Sendable {
    let text: String
    let staleResources: [ResourceCleanupEntry]
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let language: AppLanguage
    private let settingsStore = WuwaSettingsStore()
    private let versionField = NSTextField(string: "")
    private let externalRootField = NSTextField(string: "")
    private let containerField = NSTextField(string: "")
    private let appPathField = NSTextField(string: "")
    private let closedCheckBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let pathPreview = NSTextField(wrappingLabelWithString: "")
    private let advancedStack = NSStackView()
    private let logView = NSTextView()
    private let statusBadge: StatusBadgeView
    private let operationProgress = NSProgressIndicator()
    private let operationProgressLabel = NSTextField(labelWithString: "")
    private var allButtons: [NSButton] = []
    private var hasCompletedStatusCheck = false
    private var currentOperationName: String?

    init(language: AppLanguage) {
        self.language = language
        statusBadge = StatusBadgeView(language: language)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1188, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WuwaAutoMover"
        window.center()
        window.minSize = NSSize(width: 980, height: 700)
        super.init(window: window)
        window.delegate = self

        loadSavedSettings()
        buildInterface()
        refreshPathPreview()
        appendLog(t("WuwaAutoMover is ready. Review the settings, then check the current status.", "WuwaAutoMover 已就緒。請先檢查設定與目前狀態。"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func t(_ english: String, _ traditionalChinese: String) -> String {
        language.text(english, traditionalChinese)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(sender)
        return false
    }

    func confirmTerminationIfNeeded() -> Bool {
        guard let currentOperationName else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("An operation is still running", "操作仍在執行中")
        alert.informativeText = t(
            "\"\(currentOperationName)\" has not finished. Quitting now may leave files in an incomplete state. Do you really want to quit?",
            "「\(currentOperationName)」尚未完成。現在關閉可能讓檔案停留在未完成狀態。確定仍要關閉嗎？"
        )
        alert.addButton(withTitle: t("Keep Running", "繼續執行"))
        let quitButton = alert.addButton(withTitle: t("Quit Anyway", "仍要關閉"))
        quitButton.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        let header = makeHeader()
        let body = NSSplitView()
        body.isVertical = true
        body.dividerStyle = .thin
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(makeSettingsPane())
        body.addArrangedSubview(makeWorkspacePane())

        root.addArrangedSubview(header)
        root.addArrangedSubview(UIFactory.separator())
        root.addArrangedSubview(body)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            header.heightAnchor.constraint(equalToConstant: 82),
            body.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        configureFields()
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "externaldrive.fill.badge.checkmark", accessibilityDescription: "WuwaAutoMover")
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)

        let title = NSTextField(labelWithString: "WuwaAutoMover")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = UIFactory.secondaryText(t(
            "Move Wuthering Waves resources to an external disk while keeping recoverable local entry points.",
            "把鳴潮資源安全移到外接硬碟，並保留可復原的本機入口。"
        ))
        let copy = NSStackView(views: [title, subtitle])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 2

        let row = NSStackView(views: [icon, copy, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38)
        ])
        return container
    }

    private func makeSettingsPane() -> NSView {
        let visual = NSVisualEffectView()
        visual.material = .sidebar
        visual.blendingMode = .behindWindow
        visual.translatesAutoresizingMaskIntoConstraints = false
        visual.widthAnchor.constraint(equalToConstant: 365).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(stack)

        stack.addArrangedSubview(UIFactory.sectionTitle(t("Step 1 · Paths", "步驟 1 · 設定路徑")))
        stack.addArrangedSubview(UIFactory.secondaryText(t(
            "Enter the version, then select the external destination and game app. The disk name is detected from the folder path.",
            "填寫版本，並選擇外接目的資料夾與遊戲 App。程式會從資料夾路徑自動取得外接硬碟名稱。"
        )))
        addFullWidth(fieldGroup(t("Resource version", "資源版本"), field: versionField), to: stack)
        addFullWidth(fieldGroup(t("External destination", "外接目的資料夾"), field: externalRootField, button: iconButton("folder", t("Select external destination", "選擇外接目的資料夾"), #selector(selectExternalRoot))), to: stack)
        addFullWidth(fieldGroup("WutheringWaves.app", field: appPathField, button: iconButton("app", t("Select app", "選擇 App"), #selector(selectAppPath))), to: stack)

        let advancedToggle = NSButton(title: t("Advanced settings", "進階設定"), target: self, action: #selector(toggleAdvanced(_:)))
        advancedToggle.bezelStyle = .disclosure
        advancedToggle.state = .off
        allButtons.append(advancedToggle)
        stack.addArrangedSubview(advancedToggle)

        advancedStack.orientation = .vertical
        advancedStack.alignment = .leading
        advancedStack.spacing = 8
        let containerGroup = fieldGroup("App container ID", field: containerField)
        advancedStack.addArrangedSubview(containerGroup)
        containerGroup.widthAnchor.constraint(equalTo: advancedStack.widthAnchor).isActive = true
        advancedStack.isHidden = true
        stack.addArrangedSubview(advancedStack)
        advancedStack.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true

        stack.addArrangedSubview(UIFactory.separator())
        stack.addArrangedSubview(UIFactory.sectionTitle(t("Path preview", "路徑預覽")))
        pathPreview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathPreview.textColor = .secondaryLabelColor
        pathPreview.lineBreakMode = .byCharWrapping
        stack.addArrangedSubview(pathPreview)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(UIFactory.secondaryText(t(
            "Settings are saved in ~/Library/Application Support/WuwaAutoMover/config.json",
            "設定儲存在 ~/Library/Application Support/WuwaAutoMover/config.json"
        )))

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visual.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
            pathPreview.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)
        ])
        return visual
    }

    private func makeWorkspacePane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let statusStep = makeStatusStep()
        stack.addArrangedSubview(statusStep)
        statusStep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44).isActive = true
        stack.addArrangedSubview(UIFactory.separator())
        stack.addArrangedSubview(UIFactory.sectionTitle(t("Step 3 · Choose a workflow", "步驟 3 · 選擇移動方案")))
        stack.addArrangedSubview(UIFactory.secondaryText(t(
            "Confirm that all related apps are closed, then run A. Try B or C only if A does not work.",
            "先勾選下方關閉程式確認，再執行方案 A。只有 A 無法運作時，才依序嘗試 B 或 C。"
        )))

        let confirmationBand = makeConfirmationBand()
        stack.addArrangedSubview(confirmationBand)
        confirmationBand.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44).isActive = true

        let recommended = WorkflowOptionView(kind: .recommended, language: language, target: self, action: #selector(runRecommended))
        let wholeClient = WorkflowOptionView(kind: .wholeClient, language: language, target: self, action: #selector(linkWholeClient))
        let fallback = WorkflowOptionView(kind: .fallback, language: language, target: self, action: #selector(createSymlinks))
        for view in [recommended, wholeClient, fallback] {
            allButtons.append(view.actionButton)
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44).isActive = true
        }

        let utilityRow = NSStackView()
        utilityRow.orientation = .horizontal
        utilityRow.spacing = 8
        let openButton = trackedButton(title: t("Open external folder", "開啟外接資料夾"), symbol: "folder", action: #selector(openExternalFolder))
        let codesignButton = trackedButton(title: t("Codesign only", "只執行 Codesign"), symbol: "signature", action: #selector(runCodesign))
        let removeButton = trackedButton(title: t("Remove symlinks", "移除 symlink"), symbol: "link.badge.minus", action: #selector(removeSymlinks))
        removeButton.contentTintColor = .systemRed
        utilityRow.addArrangedSubview(openButton)
        utilityRow.addArrangedSubview(codesignButton)
        utilityRow.addArrangedSubview(removeButton)
        stack.addArrangedSubview(utilityRow)

        stack.addArrangedSubview(UIFactory.separator())
        stack.addArrangedSubview(makeLogPane())

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeStatusStep() -> NSView {
        let step = NSTextField(labelWithString: t("Step 2", "步驟 2"))
        step.font = .systemFont(ofSize: 11, weight: .bold)
        step.textColor = .controlAccentColor

        let title = NSTextField(labelWithString: t("Check the current status first", "先檢查目前狀態"))
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let detail = UIFactory.secondaryText(t(
            "Check the external disk, game app, and symlinks. Run this first after every launch.",
            "確認外接硬碟、遊戲 App 與目前 symlink 狀態。這是每次啟動後的第一個操作。"
        ))
        let copy = NSStackView(views: [step, title, detail])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3

        let statusButton = trackedButton(title: t("Check now", "開始檢查"), symbol: "checklist", action: #selector(checkStatus))
        statusButton.controlSize = .large
        statusButton.bezelColor = .controlAccentColor
        statusButton.keyEquivalent = "\r"
        statusButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [copy, NSView(), statusBadge, statusButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.borderWidth = 1.5
        container.layer?.borderColor = NSColor.controlAccentColor.cgColor
        container.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        container.layer?.cornerRadius = 6
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.heightAnchor.constraint(equalToConstant: 92)
        ])
        return container
    }

    private func makeConfirmationBand() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: t("Required confirmation", "執行前必要確認"))
        icon.contentTintColor = .systemOrange
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 19, weight: .semibold)

        let title = NSTextField(labelWithString: t("Required before running", "執行前必要確認"))
        title.font = .systemFont(ofSize: 12, weight: .bold)
        title.textColor = .systemOrange

        closedCheckBox.title = t(
            "The game, Launcher, App Store, and all downloads are fully closed",
            "遊戲、Launcher、App Store 與下載程序都已完全關閉"
        )
        closedCheckBox.controlSize = .large
        closedCheckBox.font = .systemFont(ofSize: 13, weight: .semibold)
        closedCheckBox.target = self
        closedCheckBox.action = #selector(confirmationChanged(_:))
        closedCheckBox.setAccessibilityHelp(t(
            "Required before moving files or changing symlinks",
            "執行移動或 symlink 操作前必須勾選"
        ))

        let copy = NSStackView(views: [title, closedCheckBox])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4

        let row = NSStackView(views: [icon, copy])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = 6
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            container.heightAnchor.constraint(equalToConstant: 68)
        ])
        return container
    }

    private func makeLogPane() -> NSView {
        let title = UIFactory.sectionTitle(t("Activity log", "執行記錄"))
        let copyButton = iconButton("doc.on.doc", t("Copy all log text", "複製全部記錄"), #selector(copyLog))
        let clearButton = iconButton("trash", t("Clear log", "清除記錄"), #selector(clearLog))

        operationProgress.style = .spinning
        operationProgress.controlSize = .small
        operationProgress.isIndeterminate = true
        operationProgress.isHidden = true
        operationProgressLabel.font = .systemFont(ofSize: 11, weight: .medium)
        operationProgressLabel.textColor = .secondaryLabelColor
        operationProgressLabel.lineBreakMode = .byTruncatingTail
        operationProgressLabel.isHidden = true
        operationProgressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [title, operationProgress, operationProgressLabel, NSView(), copyButton, clearButton])
        header.orientation = .horizontal
        header.alignment = .centerY

        logView.isEditable = false
        logView.isSelectable = true
        logView.allowsUndo = false
        logView.usesFindBar = true
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 10, height: 8)
        logView.backgroundColor = .textBackgroundColor
        logView.textColor = .labelColor
        logView.setAccessibilityLabel(t("Activity log; selectable and copyable", "執行記錄，可選取並複製"))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = logView

        let stack = NSStackView(views: [header, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
        return stack
    }

    private func fieldGroup(_ title: String, field: NSTextField, button: NSButton? = nil) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.distribution = .fill
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controls.addArrangedSubview(field)
        if let button { controls.addArrangedSubview(button) }

        let stack = NSStackView(views: [label, controls])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
    }

    private func iconButton(_ symbol: String, _ toolTip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .rounded
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        allButtons.append(button)
        return button
    }

    private func trackedButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = UIFactory.button(title: title, symbol: symbol, target: self, action: action)
        allButtons.append(button)
        return button
    }

    private func configureFields() {
        let fields = [versionField, externalRootField, containerField, appPathField]
        for field in fields {
            field.delegate = self
            field.target = self
            field.action = #selector(fieldChanged)
        }
        versionField.placeholderString = WuwaPlaceholders.version
        externalRootField.placeholderString = "/Volumes/T7/WuwaData"
        containerField.placeholderString = WuwaPlaceholders.appContainerID
        appPathField.placeholderString = WuwaPlaceholders.appPath
    }

    private func loadSavedSettings() {
        let settings = settingsStore.load()
        versionField.stringValue = settings.version
        if settings.volumeName.isEmpty || settings.externalRoot.isEmpty {
            externalRootField.stringValue = ""
        } else {
            externalRootField.stringValue = "/Volumes/\(settings.volumeName)/\(settings.externalRoot)"
        }
        containerField.stringValue = settings.appContainerID
        appPathField.stringValue = settings.appPath
    }

    @objc private func toggleAdvanced(_ sender: NSButton) {
        advancedStack.isHidden = sender.state != .on
    }

    @objc private func confirmationChanged(_ sender: NSButton) {
        sender.setAccessibilityValue(sender.state == .on
            ? t("Confirmed", "已確認")
            : t("Not confirmed", "尚未確認"))
    }

    @objc private func fieldChanged() {
        refreshPathPreview()
        saveCurrentConfigIfValid()
        hasCompletedStatusCheck = false
        statusBadge.setState(.idle)
    }

    func controlTextDidChange(_ obj: Notification) {
        fieldChanged()
    }

    @objc private func selectExternalRoot() {
        let currentPath = externalRootField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = FileManager.default.fileExists(atPath: currentPath) ? currentPath : "/Volumes"
        let panel = directoryPanel(
            title: t("Select external destination", "選擇外接目的資料夾"),
            message: t(
                "Choose the folder on your external disk where Wuthering Waves data will be stored.",
                "請選擇外接硬碟內存放鳴潮資料的資料夾。"
            ),
            path: base
        )
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            if applyExternalRoot(url.path) {
                fieldChanged()
            }
        }
    }

    @objc private func selectAppPath() {
        let panel = NSOpenPanel()
        panel.title = t("Select WutheringWaves.app", "選擇 WutheringWaves.app")
        panel.message = t(
            "Select the WutheringWaves.app installed by the App Store.",
            "請選擇 App Store 安裝的 WutheringWaves.app。"
        )
        if let location = try? externalLocation(from: externalRootField.stringValue) {
            let externalApplications = "/Volumes/\(location.volumeName)/Applications"
            let startPath = FileManager.default.fileExists(atPath: externalApplications)
                ? externalApplications
                : "/Volumes/\(location.volumeName)"
            panel.directoryURL = URL(fileURLWithPath: startPath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        if panel.runModal() == .OK, let url = panel.url {
            setField(appPathField, to: url.path)
            readContainerIDFromSelectedApp()
            fieldChanged()
        }
    }

    private func directoryPanel(title: String, message: String, path: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.directoryURL = URL(fileURLWithPath: path)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel
    }

    @objc private func checkStatus() {
        let config: WuwaConfig
        do {
            config = try currentConfig()
            try settingsStore.save(config.storedSettings)
        } catch {
            statusBadge.setState(.failed)
            showError(error)
            return
        }

        hasCompletedStatusCheck = false
        statusBadge.setState(.checking)
        let operationName = t("Check current status", "檢查目前狀態")
        beginOperation(operationName)
        appendLog("\n==> \(operationName)")

        let coreLanguage = language.coreLanguage
        DispatchQueue.global(qos: .userInitiated).async {
            let mover = WuwaMover(language: coreLanguage)
            let result = Result {
                StatusCheckOutput(
                    text: mover.describe(status: mover.status(config: config)),
                    staleResources: try mover.staleResourceEntries(config: config)
                )
            }

            Task { @MainActor in
                switch result {
                case .success(let output):
                    self.appendLog(output.text)
                    self.hasCompletedStatusCheck = true
                    self.statusBadge.setState(.ready)

                    guard !output.staleResources.isEmpty else {
                        self.appendLog(self.t("No other resource versions were found.", "未發現其他版本資源。"))
                        self.finishOperation()
                        return
                    }

                    self.appendLog(self.t(
                        "Found \(output.staleResources.count) resource items outside the current version.",
                        "找到 \(output.staleResources.count) 個其他版本資源項目。"
                    ))
                    if self.confirmStaleResourceDeletion(output.staleResources, currentVersion: config.version) {
                        self.deleteStaleResources(output.staleResources, config: config)
                    } else {
                        self.appendLog(self.t(
                            "The other resource versions were kept.",
                            "使用者選擇保留其他版本資源。"
                        ))
                        self.finishOperation()
                    }
                case .failure(let error):
                    self.appendLog("❌ \(error.localizedDescription)")
                    self.statusBadge.setState(.failed)
                    self.showError(error)
                    self.finishOperation()
                }
            }
        }
    }

    private func confirmStaleResourceDeletion(
        _ entries: [ResourceCleanupEntry],
        currentVersion: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("Other resource versions found", "找到其他版本的資源")
        alert.informativeText = t(
            "Version \(currentVersion) will be kept. Fully close the game and downloads first. Deleting permanently removes every item below, including Video and data targeted by symlinks.",
            "目前版本 \(currentVersion) 會保留。請先完全關閉遊戲與下載程序；選擇刪除後，下列項目會永久移除，包含 Video 與 symlink 指向的實際資料。"
        )
        alert.addButton(withTitle: t("Keep", "保留"))
        let deleteButton = alert.addButton(withTitle: t("Delete All", "全部刪除"))
        deleteButton.hasDestructiveAction = true

        let list = entries
            .map { entry in
                let target = entry.symbolicLinkTarget.map {
                    "\n  -> \($0)\(t(" (target data will also be deleted)", "（實際資料也會刪除）"))"
                } ?? ""
                return "[\(entry.locationLabel)]\n\(entry.path)\(target)"
            }
            .joined(separator: "\n\n")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: 560, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = list
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        return alert.runModal() == .alertSecondButtonReturn
    }

    private func deleteStaleResources(_ entries: [ResourceCleanupEntry], config: WuwaConfig) {
        currentOperationName = t("Delete other resource versions", "刪除其他版本資源")
        appendLog(t("Deleting other resource versions...", "開始刪除其他版本資源..."))
        let coreLanguage = language.coreLanguage
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try WuwaMover(language: coreLanguage).removeStaleResourceEntries(entries, config: config).text
            }
            Task { @MainActor in
                switch result {
                case .success(let text):
                    self.appendLog(text)
                    self.statusBadge.setState(.ready)
                case .failure(let error):
                    self.appendLog("❌ \(error.localizedDescription)")
                    self.statusBadge.setState(.failed)
                    self.showError(error)
                }
                self.finishOperation()
            }
        }
    }

    @objc private func runRecommended() {
        guard mutationIsConfirmed() else { return }
        let coreLanguage = language.coreLanguage
        runOperation(
            t("Recommended: Codesign + link version", "推薦：Codesign + 連結版本"),
            progressMessage: codesignProgressMessage()
        ) { config in
            try WuwaMover(language: coreLanguage).createRecommendedSetup(config: config, administratorPrivileges: true).text
        }
    }

    @objc private func linkWholeClient() {
        guard mutationIsConfirmed() else { return }
        let coreLanguage = language.coreLanguage
        runOperation(t("Link the entire Client", "整個 Client symlink")) { config in
            try WuwaMover(language: coreLanguage).createClientSymlink(config: config).text
        }
    }

    @objc private func createSymlinks() {
        guard mutationIsConfirmed() else { return }
        let coreLanguage = language.coreLanguage
        runOperation(t("Conservative dual-path", "保守雙路徑")) { config in
            try WuwaMover(language: coreLanguage).createConservativeFallbackSymlinks(config: config).text
        }
    }

    @objc private func removeSymlinks() {
        guard mutationIsConfirmed() else { return }
        let coreLanguage = language.coreLanguage
        runOperation(t("Remove symlinks", "移除 symlink")) { config in
            try WuwaMover(language: coreLanguage).removeSymlinks(config: config).text
        }
    }

    @objc private func runCodesign() {
        guard mutationIsConfirmed() else { return }
        let coreLanguage = language.coreLanguage
        runOperation(
            "Codesign WutheringWaves.app",
            progressMessage: codesignProgressMessage()
        ) { config in
            try WuwaMover(language: coreLanguage).codesignApp(config: config, administratorPrivileges: true).text
        }
    }

    @objc private func openExternalFolder() {
        do {
            let config = try currentConfig()
            let path = FileManager.default.fileExists(atPath: config.externalTarget) ? config.externalTarget : config.externalBase
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } catch {
            showError(error)
        }
    }

    @objc private func clearLog() {
        logView.string = ""
    }

    @objc private func copyLog() {
        guard !logView.string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logView.string, forType: .string)
    }

    private func currentConfig() throws -> WuwaConfig {
        let location = try externalLocation(from: externalRootField.stringValue)
        return try WuwaConfig(
            version: versionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            volumeName: location.volumeName,
            externalRoot: location.relativeRoot,
            appContainerID: containerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            appPath: appPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.coreLanguage
        )
    }

    private func externalLocation(from rawPath: String) throws -> (volumeName: String, relativeRoot: String, fullPath: String) {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw WuwaError(t("Select an external destination folder.", "請選擇外接目的資料夾。"))
        }

        let fullPath = (trimmedPath as NSString).standardizingPath
        let components = fullPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 3, components[0] == "Volumes" else {
            throw WuwaError(t(
                "The destination must be a folder inside an external disk under /Volumes, not the volume root itself.",
                "目的資料夾必須位於 /Volumes 下的外接硬碟內，且不能只選擇磁碟根目錄。"
            ))
        }

        return (
            volumeName: components[1],
            relativeRoot: components.dropFirst(2).joined(separator: "/"),
            fullPath: fullPath
        )
    }

    private func applyExternalRoot(_ path: String) -> Bool {
        do {
            let location = try externalLocation(from: path)
            setField(externalRootField, to: location.fullPath)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    private func setField(_ field: NSTextField, to value: String) {
        field.stringValue = value
        field.needsDisplay = true
        window?.makeFirstResponder(nil)
    }

    private func readContainerIDFromSelectedApp() {
        let appPath = appPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appPath.isEmpty else { return }
        let infoPlist = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlist),
              let bundleID = info["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty
        else { return }
        containerField.stringValue = bundleID
    }

    private func refreshPathPreview() {
        do {
            let config = try currentConfig()
            pathPreview.stringValue = t(
                "External resources\n\(config.externalTarget)\n\nLocal entry point\n\(config.source2)",
                "外接資源\n\(config.externalTarget)\n\n本機入口\n\(config.source2)"
            )
        } catch {
            pathPreview.stringValue = error.localizedDescription
        }
    }

    private func mutationIsConfirmed() -> Bool {
        guard hasCompletedStatusCheck else {
            showGuidance(
                title: t("Complete Step 2 first", "請先完成步驟 2"),
                message: t(
                    "Click Check Now and review the disk and symlink status before running a workflow.",
                    "按下「開始檢查」，確認目前磁碟與 symlink 狀態後再執行移動方案。"
                )
            )
            return false
        }
        guard closedCheckBox.state == .on else {
            showGuidance(
                title: t("Complete the required confirmation", "請先完成執行前確認"),
                message: t(
                    "Close the game, Launcher, App Store, and downloads, then select the confirmation checkbox in Step 3.",
                    "關閉遊戲、Launcher、App Store 與下載程序，再勾選步驟 3 上方的確認框。"
                )
            )
            return false
        }
        return true
    }

    private func runOperation(
        _ name: String,
        progressMessage: String? = nil,
        updatesStatus: Bool = false,
        work: @escaping @Sendable (WuwaConfig) throws -> String
    ) {
        let config: WuwaConfig
        do {
            config = try currentConfig()
            try settingsStore.save(config.storedSettings)
        } catch {
            if updatesStatus { statusBadge.setState(.failed) }
            showError(error)
            return
        }

        beginOperation(name)
        appendLog("\n==> \(name)")
        if let progressMessage {
            appendLog(progressMessage)
            setOperationProgress(progressMessage)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try work(config) }
            Task { @MainActor in
                switch result {
                case .success(let text):
                    self.appendLog(text)
                    if updatesStatus {
                        self.hasCompletedStatusCheck = true
                        self.statusBadge.setState(.ready)
                    }
                case .failure(let error):
                    self.appendLog("❌ \(error.localizedDescription)")
                    if updatesStatus { self.statusBadge.setState(.failed) }
                    self.showError(error)
                }
                self.setOperationProgress(nil)
                self.finishOperation()
            }
        }
    }

    private func codesignProgressMessage() -> String {
        t(
            "Codesigning WutheringWaves.app. This can take several minutes; keep WuwaAutoMover open.",
            "正在 Codesign WutheringWaves.app。這可能需要數分鐘，請保持 WuwaAutoMover 開啟。"
        )
    }

    private func setOperationProgress(_ message: String?) {
        if let message {
            operationProgressLabel.stringValue = message
            operationProgressLabel.toolTip = message
            operationProgress.isHidden = false
            operationProgressLabel.isHidden = false
            operationProgress.startAnimation(nil)
        } else {
            operationProgress.stopAnimation(nil)
            operationProgress.isHidden = true
            operationProgressLabel.isHidden = true
            operationProgressLabel.stringValue = ""
            operationProgressLabel.toolTip = nil
        }
    }

    private func saveCurrentConfigIfValid() {
        guard let config = try? currentConfig() else { return }
        try? settingsStore.save(config.storedSettings)
    }

    private func beginOperation(_ name: String) {
        currentOperationName = name
        setControlsEnabled(false)
    }

    private func finishOperation() {
        currentOperationName = nil
        setControlsEnabled(true)
    }

    private func setControlsEnabled(_ enabled: Bool) {
        [versionField, externalRootField, containerField, appPathField, closedCheckBox].forEach { $0.isEnabled = enabled }
        allButtons.forEach { $0.isEnabled = enabled }
    }

    private func appendLog(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        logView.textStorage?.append(NSAttributedString(string: text + "\n", attributes: attributes))
        logView.scrollToEndOfDocument(nil)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("Operation failed", "操作失敗")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showGuidance(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: t("OK", "知道了"))
        alert.runModal()
    }
}
