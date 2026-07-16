import Cocoa
import WuwaAutoMoverCore

enum AppLanguage: String, Sendable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var coreLanguage: WuwaLanguage {
        switch self {
        case .english: .english
        case .traditionalChinese: .traditionalChinese
        }
    }

    func text(_ english: String, _ traditionalChinese: String) -> String {
        switch self {
        case .english: english
        case .traditionalChinese: traditionalChinese
        }
    }
}

@MainActor
enum AppLanguagePreference {
    private static let key = "interfaceLanguage"

    static func load() -> AppLanguage? {
        guard let value = UserDefaults.standard.string(forKey: key) else { return nil }
        return AppLanguage(rawValue: value)
    }

    static func save(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }

    static func chooseLanguage() -> AppLanguage {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Choose Interface Language / 選擇介面語言"
        alert.informativeText = "This choice is saved for future launches.\n此選擇會儲存並套用到之後啟動。"
        alert.addButton(withTitle: "繁體中文")
        alert.addButton(withTitle: "English")
        return alert.runModal() == .alertSecondButtonReturn ? .english : .traditionalChinese
    }
}
