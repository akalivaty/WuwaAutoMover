import Foundation
import WuwaAutoMoverCore

enum Command: String {
    case status
    case link
    case unlink
    case codesign
    case help
}

struct CLIOptions {
    var command: Command = .help
    var version = "3.2.0"
    var volume = "T7"
    var externalRoot = "WuwaData"
    var containerID = "com.kurogame.wutheringwaves.global"
    var appPath = "/Volumes/T7/Applications/WutheringWaves.app"
    var yes = false
    var admin = false
}

func usage() -> String {
    """
    WuwaAutoMover command line

    Usage:
      wuwa-auto-mover status [options]
      wuwa-auto-mover link --yes [options]
      wuwa-auto-mover unlink --yes [options]
      wuwa-auto-mover codesign [--admin] [options]

    Options:
      --version <value>        Wuthering Waves resource version. Default: 3.2.0
      --volume <name>          External volume name under /Volumes. Default: T7
      --external-root <path>   Folder under the external volume. Default: WuwaData
      --container-id <id>      App container ID. Default: com.kurogame.wutheringwaves.global
      --app-path <path>        WutheringWaves.app path for codesign.
      --yes                   Required for link/unlink after closing the game.
      --admin                 Use macOS administrator prompt for codesign.
      -h, --help              Show this help.
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
        throw WuwaError("`link` / `unlink` 會修改本機資源入口。請先完全關閉遊戲、Launcher、App Store 與下載程序，然後加上 --yes。")
    }
}

do {
    let options = try parse(Array(CommandLine.arguments.dropFirst()))
    if options.command == .help {
        print(usage())
        exit(0)
    }

    let config = try WuwaConfig(
        version: options.version,
        volumeName: options.volume,
        externalRoot: options.externalRoot,
        appContainerID: options.containerID,
        appPath: options.appPath
    )
    let mover = WuwaMover()

    switch options.command {
    case .status:
        print(mover.describe(status: mover.status(config: config)))
    case .link:
        try requireYes(options)
        print(try mover.createOrUpdateSymlinks(config: config).text)
    case .unlink:
        try requireYes(options)
        print(try mover.removeSymlinks(config: config).text)
    case .codesign:
        print(try mover.codesignApp(config: config, administratorPrivileges: options.admin).text)
    case .help:
        print(usage())
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
