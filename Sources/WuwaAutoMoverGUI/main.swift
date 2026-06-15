import Cocoa
import WuwaAutoMoverCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private let settingsStore = WuwaSettingsStore()
    private let versionField = NSTextField(string: "")
    private let volumeField = NSTextField(string: "")
    private let externalRootField = NSTextField(string: "")
    private let containerField = NSTextField(string: "")
    private let appPathField = NSTextField(string: "")
    private let closedCheckBox = NSButton(checkboxWithTitle: "我已完全關閉鳴潮、Launcher、App Store 與下載程序", target: nil, action: nil)
    private let pathPreview = NSTextField(labelWithString: "")
    private let logView = NSTextView()
    private var actionButtons: [NSButton] = []
    private var allButtons: [NSButton] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSavedSettings()
        buildWindow()
        refreshPathPreview()
        appendLog("WuwaAutoMover 已啟動。請先輸入或確認設定，設定會自動記住。")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WuwaAutoMover"
        window.center()
        window.minSize = NSSize(width: 860, height: 680)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        window.contentView = root

        let title = NSTextField(labelWithString: "WuwaAutoMover")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString: "建議先 codesign 讓 App Store 版離開 sandbox，再只處理 ~/Library/Client。若不確定目前路徑，最後再使用保守雙路徑方法。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)

        let form = NSGridView(views: [
            [label("版本號"), versionField, emptyView()],
            [label("外接硬碟"), volumeField, makeButton(title: "選擇", symbol: "externaldrive", action: #selector(selectVolume))],
            [label("外接資料夾"), externalRootField, makeButton(title: "選擇", symbol: "folder", action: #selector(selectExternalRoot))],
            [label("WutheringWaves.app"), appPathField, makeButton(title: "選擇 App", symbol: "app", action: #selector(selectAppPath))],
            [label("App container ID"), containerField, emptyView()]
        ])
        form.rowSpacing = 9
        form.columnSpacing = 12
        form.translatesAutoresizingMaskIntoConstraints = false
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).width = 600
        form.column(at: 2).width = 120
        root.addArrangedSubview(form)

        for field in [versionField, volumeField, externalRootField, containerField, appPathField] {
            field.placeholderString = placeholder(for: field)
            field.delegate = self
            field.target = self
            field.action = #selector(fieldChanged(_:))
        }

        pathPreview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pathPreview.textColor = .secondaryLabelColor
        pathPreview.maximumNumberOfLines = 0
        pathPreview.lineBreakMode = .byCharWrapping
        root.addArrangedSubview(pathPreview)

        closedCheckBox.target = self
        closedCheckBox.action = #selector(checkBoxChanged(_:))
        root.addArrangedSubview(closedCheckBox)

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 10
        statusRow.alignment = .centerY
        let statusButton = makeButton(title: "檢查目前狀態", symbol: "checklist", action: #selector(checkStatus))
        let openButton = makeButton(title: "打開外接資料夾", symbol: "folder", action: #selector(openExternalFolder))
        let codesignButton = makeButton(title: "只執行 Codesign", symbol: "signature", action: #selector(runCodesign))
        statusRow.addArrangedSubview(statusButton)
        statusRow.addArrangedSubview(openButton)
        statusRow.addArrangedSubview(codesignButton)
        root.addArrangedSubview(statusRow)

        let actionTitle = NSTextField(labelWithString: "依序選擇一個方案")
        actionTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(actionTitle)

        let recommendedButton = makeButton(title: "執行選項 1", symbol: "1.circle.fill", action: #selector(runRecommended))
        let clientButton = makeButton(title: "執行選項 2", symbol: "2.circle.fill", action: #selector(linkWholeClient))
        let fallbackButton = makeButton(title: "執行選項 3", symbol: "3.circle.fill", action: #selector(createSymlinks))
        let removeButton = makeButton(title: "移除 symlink", symbol: "link.badge.minus", action: #selector(removeSymlinks))

        let actionList = NSStackView()
        actionList.orientation = .vertical
        actionList.alignment = .leading
        actionList.spacing = 8
        actionList.addArrangedSubview(actionRow(
            title: "1. 推薦：安裝完 App 後先 Codesign，再只連結資源版本資料夾",
            detail: "適合全新安裝或已確認 app 不在 sandbox。通常不需要處理 container 路徑。",
            button: recommendedButton
        ))
        actionList.addArrangedSubview(actionRow(
            title: "2. 第二選擇：把整個 ~/Library/Client 指到外接硬碟",
            detail: "比較省事，但移動的不只是下載資源。請先完成 codesign 並關閉遊戲。",
            button: clientButton
        ))
        actionList.addArrangedSubview(actionRow(
            title: "3. 最保守：同時處理 container 與 ~/Library 兩條資源路徑",
            detail: "不知道目前遊戲走哪條路徑、或 App Store 更新後恢復 sandbox 時再用。",
            button: fallbackButton
        ))
        actionList.addArrangedSubview(actionRow(
            title: "清理：移除目前建立的 symlink",
            detail: "只移除本機入口 symlink 並重建空資料夾，不刪外接硬碟資料。",
            button: removeButton
        ))
        root.addArrangedSubview(actionList)

        recommendedButton.toolTip = "先 codesign，再只把 ~/Library/Client/Saved/Resources/<版本> 指到外接硬碟。"
        clientButton.toolTip = "把整個 ~/Library/Client 指到外接硬碟。"
        fallbackButton.toolTip = "先同步既有本機資源，再把 container 與 ~/Library 兩個入口都改成 symlink。"
        removeButton.toolTip = "只移除兩個入口的 symlink 並重建空資料夾，不刪外接硬碟資料。"
        codesignButton.toolTip = "以管理員授權執行 codesign。"

        actionButtons = [recommendedButton, clientButton, fallbackButton, removeButton, codesignButton]

        let logLabel = NSTextField(labelWithString: "執行記錄")
        logLabel.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(logLabel)

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.textContainerInset = NSSize(width: 8, height: 8)
        logView.drawsBackground = true
        logView.backgroundColor = .textBackgroundColor
        logView.textColor = .labelColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = logView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scroll)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            subtitle.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
            pathPreview.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        updateMutationButtons()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            button.image = image
            button.imagePosition = .imageLeading
        }
        allButtons.append(button)
        return button
    }

    private func emptyView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func actionRow(title: String, detail: String, button: NSButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        button.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        row.addArrangedSubview(button)
        row.addArrangedSubview(textStack)

        NSLayoutConstraint.activate([
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 620)
        ])

        return row
    }

    private func loadSavedSettings() {
        let settings = settingsStore.load()
        versionField.stringValue = settings.version
        volumeField.stringValue = settings.volumeName
        externalRootField.stringValue = settings.externalRoot
        containerField.stringValue = settings.appContainerID
        appPathField.stringValue = settings.appPath
    }

    private func placeholder(for field: NSTextField) -> String {
        if field === versionField {
            return WuwaPlaceholders.version
        }
        if field === volumeField {
            return WuwaPlaceholders.volumeName
        }
        if field === externalRootField {
            return WuwaPlaceholders.externalRoot
        }
        if field === containerField {
            return WuwaPlaceholders.appContainerID
        }
        if field === appPathField {
            return WuwaPlaceholders.appPath
        }
        return ""
    }

    private func updateMutationButtons() {
        let enabled = closedCheckBox.state == .on
        actionButtons.forEach { $0.isEnabled = enabled }
    }

    @objc private func fieldChanged(_ sender: Any) {
        refreshPathPreview()
        saveCurrentConfigIfValid()
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshPathPreview()
        saveCurrentConfigIfValid()
    }

    @objc private func checkBoxChanged(_ sender: Any) {
        updateMutationButtons()
    }

    @objc private func selectVolume() {
        let panel = NSOpenPanel()
        panel.title = "選擇外接硬碟"
        panel.message = "請選擇 /Volumes 底下的外接硬碟。"
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            volumeField.stringValue = url.lastPathComponent
            refreshPathPreview()
            saveCurrentConfigIfValid()
        }
    }

    @objc private func selectExternalRoot() {
        let panel = NSOpenPanel()
        panel.title = "選擇外接資料夾"
        panel.message = "請選擇外接硬碟上要存放 Wuwa 資料的資料夾。"
        panel.directoryURL = volumeField.stringValue.isEmpty ? URL(fileURLWithPath: "/Volumes") : URL(fileURLWithPath: "/Volumes/\(volumeField.stringValue)")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            applyExternalRoot(url.path)
            refreshPathPreview()
            saveCurrentConfigIfValid()
        }
    }

    @objc private func selectAppPath() {
        let panel = NSOpenPanel()
        panel.title = "選擇 WutheringWaves.app"
        panel.message = "請選擇 App Store 安裝的 WutheringWaves.app。"
        panel.directoryURL = volumeField.stringValue.isEmpty ? URL(fileURLWithPath: "/Applications") : URL(fileURLWithPath: "/Volumes/\(volumeField.stringValue)/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        if panel.runModal() == .OK, let url = panel.url {
            appPathField.stringValue = url.path
            readContainerIDFromSelectedApp(showErrorOnFailure: false)
            refreshPathPreview()
            saveCurrentConfigIfValid()
        }
    }

    @objc private func checkStatus() {
        runOperation("檢查狀態") { config in
            let mover = WuwaMover()
            return mover.describe(status: mover.status(config: config))
        }
    }

    @objc private func runRecommended() {
        guard mutationIsConfirmed() else { return }
        runOperation("1 推薦：Codesign + 連結版本") { config in
            try WuwaMover().createRecommendedSetup(config: config, administratorPrivileges: true).text
        }
    }

    @objc private func linkWholeClient() {
        guard mutationIsConfirmed() else { return }
        runOperation("2 整個 Client symlink") { config in
            try WuwaMover().createClientSymlink(config: config).text
        }
    }

    @objc private func createSymlinks() {
        guard mutationIsConfirmed() else { return }
        runOperation("3 保守雙路徑") { config in
            try WuwaMover().createConservativeFallbackSymlinks(config: config).text
        }
    }

    @objc private func removeSymlinks() {
        guard mutationIsConfirmed() else { return }
        runOperation("移除 symlink") { config in
            try WuwaMover().removeSymlinks(config: config).text
        }
    }

    @objc private func runCodesign() {
        guard mutationIsConfirmed() else { return }
        runOperation("Codesign App") { config in
            try WuwaMover().codesignApp(config: config, administratorPrivileges: true).text
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

    private func currentConfig() throws -> WuwaConfig {
        try WuwaConfig(
            version: versionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            volumeName: volumeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            externalRoot: externalRootField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            appContainerID: containerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            appPath: appPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func applyExternalRoot(_ path: String) {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 2, components[0] == "Volumes" else {
            externalRootField.stringValue = path
            return
        }
        volumeField.stringValue = components[1]
        if components.count > 2 {
            externalRootField.stringValue = components.dropFirst(2).joined(separator: "/")
        } else {
            externalRootField.stringValue = ""
        }
    }

    private func readContainerIDFromSelectedApp(showErrorOnFailure: Bool) {
        let appPath = appPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appPath.isEmpty else {
            if showErrorOnFailure {
                showError(WuwaError("請先選擇 WutheringWaves.app。"))
            }
            return
        }

        let infoPlist = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlist),
              let bundleID = info["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty
        else {
            if showErrorOnFailure {
                showError(WuwaError("無法從 App 讀取 CFBundleIdentifier：\(infoPlist.path)"))
            }
            return
        }

        containerField.stringValue = bundleID
        refreshPathPreview()
        saveCurrentConfigIfValid()
    }

    private func refreshPathPreview() {
        do {
            let config = try currentConfig()
            pathPreview.stringValue = """
            外接目標：\(config.externalTarget)
            外接 Client：\(config.externalClient)
            Container 入口：\(config.source1)
            使用者 Library 版本入口：\(config.source2)
            使用者 Library Client：\(config.userClient)
            """
        } catch {
            pathPreview.stringValue = error.localizedDescription
        }
    }

    private func mutationIsConfirmed() -> Bool {
        if closedCheckBox.state != .on {
            showError(WuwaError("執行前必須先確認遊戲、Launcher、App Store 與下載程序都已關閉。"))
            return false
        }
        return true
    }

    private func runOperation(_ name: String, work: @escaping @Sendable (WuwaConfig) throws -> String) {
        let config: WuwaConfig
        do {
            config = try currentConfig()
            try settingsStore.save(config.storedSettings)
        } catch {
            showError(error)
            return
        }

        setControlsEnabled(false)
        appendLog("")
        appendLog("==> \(name)")

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                result = .success(try work(config))
            } catch {
                result = .failure(error)
            }

            Task { @MainActor in
                switch result {
                case .success(let text):
                    self.appendLog(text)
                    self.setControlsEnabled(true)
                case .failure(let error):
                    self.appendLog("❌ \(error.localizedDescription)")
                    self.showError(error)
                    self.setControlsEnabled(true)
                }
            }
        }
    }

    private func saveCurrentConfigIfValid() {
        guard let config = try? currentConfig() else { return }
        try? settingsStore.save(config.storedSettings)
    }

    private func setControlsEnabled(_ enabled: Bool) {
        for control in [versionField, volumeField, externalRootField, containerField, appPathField, closedCheckBox] {
            control.isEnabled = enabled
        }
        for button in actionButtons {
            button.isEnabled = enabled && closedCheckBox.state == .on
        }
        for button in allButtons where !actionButtons.contains(button) {
            button.isEnabled = enabled
        }
    }

    private func appendLog(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
        logView.textStorage?.append(NSAttributedString(string: text + "\n", attributes: attributes))
        logView.scrollToEndOfDocument(nil)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "操作失敗"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
