import Cocoa
import WuwaAutoMoverCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let versionField = NSTextField(string: "3.2.0")
    private let volumeField = NSTextField(string: "T7")
    private let externalRootField = NSTextField(string: "WuwaData")
    private let containerField = NSTextField(string: "com.kurogame.wutheringwaves.global")
    private let appPathField = NSTextField(string: "/Volumes/T7/Applications/WutheringWaves.app")
    private let closedCheckBox = NSButton(checkboxWithTitle: "我已完全關閉鳴潮、Launcher、App Store 與下載程序", target: nil, action: nil)
    private let pathPreview = NSTextField(labelWithString: "")
    private let logView = NSTextView()
    private var actionButtons: [NSButton] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        refreshPathPreview()
        appendLog("WuwaAutoMover 已啟動。請先確認設定，再執行檢查或轉移。")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WuwaAutoMover"
        window.center()
        window.minSize = NSSize(width: 780, height: 560)

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

        let subtitle = NSTextField(wrappingLabelWithString: "把鳴潮兩個本機資源入口同步到外接硬碟，並改成指向同一個版本資料夾的 symlink。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)

        let form = NSGridView(views: [
            [label("版本號"), versionField],
            [label("外接硬碟名稱"), volumeField],
            [label("外接資料夾"), externalRootField],
            [label("App container ID"), containerField],
            [label("WutheringWaves.app"), appPathField]
        ])
        form.rowSpacing = 9
        form.columnSpacing = 12
        form.translatesAutoresizingMaskIntoConstraints = false
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).width = 560
        root.addArrangedSubview(form)

        for field in [versionField, volumeField, externalRootField, containerField, appPathField] {
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

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let statusButton = makeButton(title: "檢查狀態", symbol: "checklist", action: #selector(checkStatus))
        let createButton = makeButton(title: "建立 / 更新 symlink", symbol: "link", action: #selector(createSymlinks))
        let removeButton = makeButton(title: "移除 symlink", symbol: "link.badge.minus", action: #selector(removeSymlinks))
        let codesignButton = makeButton(title: "Codesign App", symbol: "signature", action: #selector(runCodesign))
        let openButton = makeButton(title: "打開外接資料夾", symbol: "folder", action: #selector(openExternalFolder))

        createButton.toolTip = "先同步既有本機資源，再把兩個入口改成 symlink。"
        removeButton.toolTip = "只移除兩個入口的 symlink 並重建空資料夾，不刪外接硬碟資料。"
        codesignButton.toolTip = "以管理員授權執行 codesign，處理遊戲啟動時的儲存錯誤。"

        actionButtons = [createButton, removeButton, codesignButton]
        for button in [statusButton, createButton, removeButton, codesignButton, openButton] {
            buttonRow.addArrangedSubview(button)
        }
        root.addArrangedSubview(buttonRow)

        let logLabel = NSTextField(labelWithString: "執行記錄")
        logLabel.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(logLabel)

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.textContainerInset = NSSize(width: 8, height: 8)

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
        return button
    }

    private func updateMutationButtons() {
        let enabled = closedCheckBox.state == .on
        actionButtons.forEach { $0.isEnabled = enabled }
    }

    @objc private func fieldChanged(_ sender: Any) {
        refreshPathPreview()
    }

    @objc private func checkBoxChanged(_ sender: Any) {
        updateMutationButtons()
    }

    @objc private func checkStatus() {
        runOperation("檢查狀態") { config in
            let mover = WuwaMover()
            return mover.describe(status: mover.status(config: config))
        }
    }

    @objc private func createSymlinks() {
        guard mutationIsConfirmed() else { return }
        runOperation("建立 / 更新 symlink") { config in
            try WuwaMover().createOrUpdateSymlinks(config: config).text
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

    private func refreshPathPreview() {
        do {
            let config = try currentConfig()
            pathPreview.stringValue = """
            外接目標：\(config.externalTarget)
            入口 1：\(config.source1)
            入口 2：\(config.source2)
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

    private func setControlsEnabled(_ enabled: Bool) {
        for control in [versionField, volumeField, externalRootField, containerField, appPathField, closedCheckBox] {
            control.isEnabled = enabled
        }
        for button in actionButtons {
            button.isEnabled = enabled && closedCheckBox.state == .on
        }
    }

    private func appendLog(_ text: String) {
        logView.textStorage?.append(NSAttributedString(string: text + "\n"))
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
