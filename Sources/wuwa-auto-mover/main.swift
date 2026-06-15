import Foundation
import WuwaAutoMoverCore

enum Command: String {
    case status
    case recommended
    case linkVersion = "link-version"
    case linkClient = "link-client"
    case fallbackLink = "fallback-link"
    case unlink
    case codesign
    case entitlements
    case config
    case help
}

struct CLIOptions {
    var command: Command = .help
    var version: String?
    var volume: String?
    var externalRoot: String?
    var containerID: String?
    var appPath: String?
    var yes = false
    var admin = false
}

func usage() -> String {
    """
    WuwaAutoMover command line

    Recommended order:
      1. recommended    Codesign app, then link ~/Library/Client/Saved/Resources/<version>
      2. link-client    Link the whole ~/Library/Client folder to external disk
      3. fallback-link  Conservative fallback: link both container and ~/Library resource paths

    Usage:
      wuwa-auto-mover config [options]
      wuwa-auto-mover status [options]
      wuwa-auto-mover recommended --yes [--admin] [options]
      wuwa-auto-mover link-version --yes [options]
      wuwa-auto-mover link-client --yes [options]
      wuwa-auto-mover fallback-link --yes [options]
      wuwa-auto-mover unlink --yes [options]
      wuwa-auto-mover codesign [--admin] [options]
      wuwa-auto-mover entitlements [options]

    Options:
      --version <value>        Resource version. Example: \(WuwaPlaceholders.version)
      --volume <name>          External volume under /Volumes. Example: \(WuwaPlaceholders.volumeName)
      --external-root <path>   Folder under the external volume. Example: \(WuwaPlaceholders.externalRoot)
      --container-id <id>      App container ID. Example: \(WuwaPlaceholders.appContainerID)
      --app-path <path>        WutheringWaves.app absolute path. Example: \(WuwaPlaceholders.appPath)
      --yes                   Required for filesystem-changing link/unlink operations.
      --admin                 Use macOS administrator prompt for codesign.
      -h, --help              Show this help.

    Settings are saved to:
      \(WuwaSettingsStore().configURL.path)

    The examples above are placeholders, not defaults. On first use, pass your own paths.
    """
}

func parse(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0

    if let first = args.first, let command = Command(rawValue: first) {
        options.command = command
        index = 1
    } else if args.first == "-h" || args.first == "--help" || args.isEmpty {
        options.command = .help
        index = args.isEmpty ? 0 : 1
    } else if let first = args.first {
        throw WuwaError("未知指令：\(first)\n\n\(usage())")
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--version":
            options.version = try value(after: arg, args: args, index: &index)
        case "--volume":
            options.volume = try value(after: arg, args: args, index: &index)
        case "--external-root":
            options.externalRoot = try value(after: arg, args: args, index: &index)
        case "--container-id":
            options.containerID = try value(after: arg, args: args, index: &index)
        case "--app-path":
            options.appPath = try value(after: arg, args: args, index: &index)
        case "--yes":
            options.yes = true
            index += 1
        case "--admin":
            options.admin = true
            index += 1
        case "-h", "--help":
            options.command = .help
            index += 1
        default:
            throw WuwaError("未知參數：\(arg)\n\n\(usage())")
        }
    }

    return options
}

func value(after option: String, args: [String], index: inout Int) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < args.count else {
        throw WuwaError("\(option) 需要一個值。")
    }
    index += 2
    return args[valueIndex]
}

func requireYes(_ options: CLIOptions) throws {
    if !options.yes {
        throw WuwaError("這個操作會修改本機資源入口。請先完全關閉遊戲、Launcher、App Store 與下載程序，然後加上 --yes。")
    }
}

func mergedSettings(options: CLIOptions, store: WuwaSettingsStore) -> WuwaStoredSettings {
    var settings = store.load()
    if let version = options.version { settings.version = version }
    if let volume = options.volume { settings.volumeName = volume }
    if let externalRoot = options.externalRoot { settings.externalRoot = externalRoot }
    if let containerID = options.containerID { settings.appContainerID = containerID }
    if let appPath = options.appPath { settings.appPath = appPath }
    return settings
}

func requireConfig(options: CLIOptions, store: WuwaSettingsStore) throws -> WuwaConfig {
    let settings = mergedSettings(options: options, store: store)
    let missing = [
        settings.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--version, example \(WuwaPlaceholders.version)" : nil,
        settings.volumeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--volume, example \(WuwaPlaceholders.volumeName)" : nil,
        settings.externalRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--external-root, example \(WuwaPlaceholders.externalRoot)" : nil,
        settings.appContainerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--container-id, example \(WuwaPlaceholders.appContainerID)" : nil,
        settings.appPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--app-path, example \(WuwaPlaceholders.appPath)" : nil
    ].compactMap { $0 }

    if !missing.isEmpty {
        throw WuwaError("缺少設定：\n- \(missing.joined(separator: "\n- "))\n\n先執行 `wuwa-auto-mover config ...` 或在目前指令補上參數。")
    }

    return try WuwaConfig(
        version: settings.version.trimmingCharacters(in: .whitespacesAndNewlines),
        volumeName: settings.volumeName.trimmingCharacters(in: .whitespacesAndNewlines),
        externalRoot: settings.externalRoot.trimmingCharacters(in: .whitespacesAndNewlines),
        appContainerID: settings.appContainerID.trimmingCharacters(in: .whitespacesAndNewlines),
        appPath: settings.appPath.trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

do {
    let options = try parse(Array(CommandLine.arguments.dropFirst()))
    if options.command == .help {
        print(usage())
        exit(0)
    }

    let store = WuwaSettingsStore()
    let config = try requireConfig(options: options, store: store)
    try store.save(config.storedSettings)

    let mover = WuwaMover()

    switch options.command {
    case .config:
        print("✅ 設定已儲存：\(store.configURL.path)")
        print(mover.describe(status: mover.status(config: config)))
    case .status:
        print(mover.describe(status: mover.status(config: config)))
    case .recommended:
        try requireYes(options)
        print(try mover.createRecommendedSetup(config: config, administratorPrivileges: options.admin).text)
    case .linkVersion:
        try requireYes(options)
        print(try mover.createUserResourceVersionSymlink(config: config).text)
    case .linkClient:
        try requireYes(options)
        print(try mover.createClientSymlink(config: config).text)
    case .fallbackLink:
        try requireYes(options)
        print(try mover.createConservativeFallbackSymlinks(config: config).text)
    case .unlink:
        try requireYes(options)
        print(try mover.removeSymlinks(config: config).text)
    case .codesign:
        print(try mover.codesignApp(config: config, administratorPrivileges: options.admin).text)
    case .entitlements:
        print(try mover.inspectEntitlements(config: config))
    case .help:
        print(usage())
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
