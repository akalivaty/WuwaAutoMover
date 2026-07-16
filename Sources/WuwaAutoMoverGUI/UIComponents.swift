import Cocoa

enum WorkflowKind {
    case recommended
    case wholeClient
    case fallback

    var number: String {
        switch self {
        case .recommended: "A"
        case .wholeClient: "B"
        case .fallback: "C"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .recommended: language.text("Recommended", "推薦方案")
        case .wholeClient: language.text("Move the Entire Client", "整個 Client 移到外接碟")
        case .fallback: language.text("Conservative Dual-Path", "保守雙路徑方案")
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .recommended:
            language.text(
                "Codesign first, then link only the current resource version. Best for fresh installs.",
                "先 Codesign，再只連結目前版本資源。適合全新安裝與一般情況。"
            )
        case .wholeClient:
            language.text(
                "Move all of ~/Library/Client. This is broader, but later versions need no relinking.",
                "將 ~/Library/Client 整體移到外接碟。範圍較大，但後續版本不用重設。"
            )
        case .fallback:
            language.text(
                "Handle both the container and user Library paths when the game still uses its sandbox.",
                "同時處理 container 與使用者 Library。遊戲仍走 sandbox 路徑時使用。"
            )
        }
    }

    var symbolName: String {
        switch self {
        case .recommended: "checkmark.seal.fill"
        case .wholeClient: "externaldrive.fill.badge.plus"
        case .fallback: "arrow.triangle.branch"
        }
    }
}

@MainActor
final class WorkflowOptionView: NSView {
    let actionButton: NSButton
    private let kind: WorkflowKind

    init(kind: WorkflowKind, language: AppLanguage, target: AnyObject, action: Selector) {
        self.kind = kind
        actionButton = NSButton(
            title: kind == .recommended
                ? language.text("Run Recommended", "執行推薦方案")
                : language.text("Run", "執行"),
            target: target,
            action: action
        )
        super.init(frame: .zero)

        wantsLayer = true
        layer?.borderWidth = kind == .recommended ? 1.5 : 1
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        updateAppearance()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.title(language: language))
        icon.contentTintColor = kind == .recommended ? .controlAccentColor : .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)

        let number = NSTextField(labelWithString: kind.number)
        number.font = .systemFont(ofSize: 11, weight: .bold)
        number.textColor = kind == .recommended ? .controlAccentColor : .tertiaryLabelColor

        let title = NSTextField(labelWithString: kind.title(language: language))
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        let detail = NSTextField(wrappingLabelWithString: kind.detail(language: language))
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2

        let copy = NSStackView(views: [title, detail])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3

        actionButton.bezelStyle = kind == .recommended ? .rounded : .regularSquare
        actionButton.controlSize = .large
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        if let image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: actionButton.title) {
            actionButton.image = image
            actionButton.imagePosition = .imageLeading
        }

        let row = NSStackView(views: [number, icon, copy, actionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            number.widthAnchor.constraint(equalToConstant: 10),
            heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.borderColor = (kind == .recommended ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = (kind == .recommended
            ? NSColor.controlAccentColor.withAlphaComponent(0.06)
            : NSColor.controlBackgroundColor).cgColor
    }
}

@MainActor
final class StatusBadgeView: NSView {
    enum State {
        case idle
        case checking
        case ready
        case failed
    }

    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")
    private let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false

        textField.font = .systemFont(ofSize: 12, weight: .medium)
        let stack = NSStackView(views: [iconView, textField])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14)
        ])
        setState(.idle)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setState(_ state: State) {
        let symbol: String
        let text: String
        let color: NSColor
        switch state {
        case .idle:
            symbol = "circle.dotted"
            text = language.text("Not checked", "尚未檢查")
            color = .secondaryLabelColor
        case .checking:
            symbol = "arrow.triangle.2.circlepath"
            text = language.text("Checking", "檢查中")
            color = .systemBlue
        case .ready:
            symbol = "checkmark.circle.fill"
            text = language.text("Checked", "檢查完成")
            color = .systemGreen
        case .failed:
            symbol = "exclamationmark.triangle.fill"
            text = language.text("Needs attention", "需要處理")
            color = .systemRed
        }
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        iconView.contentTintColor = color
        textField.stringValue = text
        textField.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.1).cgColor
    }
}

@MainActor
enum UIFactory {
    static func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }

    static func secondaryText(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    static func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    static func button(title: String, symbol: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            button.image = image
            button.imagePosition = .imageLeading
        }
        return button
    }
}
