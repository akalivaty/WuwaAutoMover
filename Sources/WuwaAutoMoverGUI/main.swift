import Cocoa
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let language = AppLanguagePreference.load() ?? AppLanguagePreference.chooseLanguage()
        AppLanguagePreference.save(language)

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        configureMainMenu(language: language, updaterController: updaterController)

        let controller = MainWindowController(language: language)
        mainWindowController = controller
        controller.showWindow(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mainWindowController?.confirmTerminationIfNeeded() == false
            ? .terminateCancel
            : .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func configureMainMenu(
        language: AppLanguage,
        updaterController: SPUStandardUpdaterController
    ) {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "WuwaAutoMover")
        let updateItem = NSMenuItem(
            title: language.text("Check for Updates...", "檢查更新..."),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        applicationMenu.addItem(updateItem)
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: language.text("Quit WuwaAutoMover", "結束 WuwaAutoMover"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        applicationMenu.addItem(quitItem)
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
