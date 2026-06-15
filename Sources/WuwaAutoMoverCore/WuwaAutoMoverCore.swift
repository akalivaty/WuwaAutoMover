import Foundation

public struct WuwaConfig: Sendable {
    public let version: String
    public let volumeName: String
    public let externalRoot: String
    public let appContainerID: String
    public let appPath: String

    public init(
        version: String,
        volumeName: String = "T7",
        externalRoot: String = "WuwaData",
        appContainerID: String = "com.kurogame.wutheringwaves.global",
        appPath: String = "/Volumes/T7/Applications/WutheringWaves.app"
    ) throws {
        try WuwaConfig.validatePathComponent(version, name: "版本號")
        try WuwaConfig.validatePathComponent(volumeName, name: "外接硬碟名稱")
        try WuwaConfig.validateRelativePath(externalRoot, name: "外接資料夾")
        try WuwaConfig.validatePathComponent(appContainerID, name: "App container ID")
        if appPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !appPath.hasPrefix("/") {
            throw WuwaError("WutheringWaves.app 必須是絕對路徑。")
        }

        self.version = version
        self.volumeName = volumeName
        self.externalRoot = externalRoot
        self.appContainerID = appContainerID
        self.appPath = appPath
    }

    public var externalBase: String {
        "/Volumes/\(volumeName)/\(externalRoot)/Resources"
    }

    public var externalTarget: String {
        "\(externalBase)/\(version)"
    }

    public var source1Base: String {
        "\(NSHomeDirectory())/Library/Containers/\(appContainerID)/Data/Library/Client/Saved/Resources"
    }

    public var source2Base: String {
        "\(NSHomeDirectory())/Library/Client/Saved/Resources"
    }

    public var source1: String {
        "\(source1Base)/\(version)"
    }

    public var source2: String {
        "\(source2Base)/\(version)"
    }

    private static func validatePathComponent(_ value: String, name: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WuwaError("\(name) 不能空白。")
        }
        if value.contains("/") || value == "." || value == ".." {
            throw WuwaError("\(name) 不能包含斜線或特殊路徑。")
        }
    }

    private static func validateRelativePath(_ value: String, name: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WuwaError("\(name) 不能空白。")
        }
        if value.hasPrefix("/") || value.split(separator: "/").contains("..") {
            throw WuwaError("\(name) 必須是外接硬碟底下的相對路徑。")
        }
    }
}

public struct PathStatus: Sendable {
    public let label: String
    public let path: String
    public let kind: String
    public let target: String?
}

public struct WuwaStatus: Sendable {
    public let config: WuwaConfig
    public let volumeExists: Bool
    public let externalTargetExists: Bool
    public let externalTargetSize: String?
    public let entries: [PathStatus]
}

public struct OperationResult: Sendable {
    public let lines: [String]

    public init(_ lines: [String]) {
        self.lines = lines
    }

    public var text: String {
        lines.joined(separator: "\n")
    }
}

public struct WuwaError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public final class WuwaMover {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func status(config: WuwaConfig) -> WuwaStatus {
        let volumeExists = fileManager.fileExists(atPath: "/Volumes/\(config.volumeName)")
        let externalTargetExists = fileManager.fileExists(atPath: config.externalTarget)
        let size = externalTargetExists ? try? runProcess("/usr/bin/du", arguments: ["-sh", config.externalTarget]) : nil
        return WuwaStatus(
            config: config,
            volumeExists: volumeExists,
            externalTargetExists: externalTargetExists,
            externalTargetSize: size?.trimmingCharacters(in: .whitespacesAndNewlines),
            entries: [
                pathStatus(config.source1, label: "Container 路徑"),
                pathStatus(config.source2, label: "使用者 Library 路徑")
            ]
        )
    }

    public func createOrUpdateSymlinks(config: WuwaConfig) throws -> OperationResult {
        try ensureVolumeExists(config)

        var lines: [String] = []
        lines.append("建立必要資料夾")
        try fileManager.createDirectory(atPath: config.externalTarget, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: config.source1Base, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: config.source2Base, withIntermediateDirectories: true)
        lines.append("✅ 外接目標資料夾已準備完成")

        lines.append(try syncIfRealDirectory(config.source1, label: "Container 路徑", config: config))
        lines.append(try syncIfRealDirectory(config.source2, label: "使用者 Library 路徑", config: config))
        lines.append(try replaceWithSymlink(config.source1, label: "Container 路徑", config: config))
        lines.append(try replaceWithSymlink(config.source2, label: "使用者 Library 路徑", config: config))

        lines.append("")
        lines.append("驗證結果")
        lines.append(verifyPath(config.source1, label: "Container 路徑", config: config))
        lines.append(verifyPath(config.source2, label: "使用者 Library 路徑", config: config))
        lines.append("✅ 完成。現在可以開遊戲測試。")
        return OperationResult(lines)
    }

    public func removeSymlinks(config: WuwaConfig) throws -> OperationResult {
        OperationResult([
            try removeOneSymlink(config.source1, label: "Container 路徑"),
            try removeOneSymlink(config.source2, label: "使用者 Library 路徑"),
            "✅ symlink 已移除。外接硬碟上的資料未刪除。"
        ])
    }

    public func codesignApp(config: WuwaConfig, administratorPrivileges: Bool) throws -> OperationResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: config.appPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WuwaError("找不到 WutheringWaves.app：\(config.appPath)")
        }

        let output: String
        if administratorPrivileges {
            let command = "/usr/bin/codesign --sign - --force --deep \(shellQuote(config.appPath))"
            let script = "do shell script \(appleScriptString(command)) with administrator privileges"
            output = try runProcess("/usr/bin/osascript", arguments: ["-e", script])
        } else {
            output = try runProcess("/usr/bin/codesign", arguments: ["--sign", "-", "--force", "--deep", config.appPath])
        }

        return OperationResult(["✅ codesign 已完成。", output].filter { !$0.isEmpty })
    }

    public func describe(status: WuwaStatus) -> String {
        var lines: [String] = []
        lines.append("版本號：\(status.config.version)")
        lines.append("外接目標：\(status.config.externalTarget)")
        lines.append(status.volumeExists ? "✅ 已找到外接硬碟：/Volumes/\(status.config.volumeName)" : "❌ 找不到外接硬碟：/Volumes/\(status.config.volumeName)")
        lines.append(status.externalTargetExists ? "✅ 外接目標存在" : "⚠️ 外接目標不存在")
        if let size = status.externalTargetSize {
            lines.append("外接目標容量：\(size)")
        }
        for entry in status.entries {
            lines.append("")
            lines.append("[\(entry.label)]")
            lines.append("路徑：\(entry.path)")
            lines.append("類型：\(entry.kind)")
            if let target = entry.target {
                lines.append("指向：\(target)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func ensureVolumeExists(_ config: WuwaConfig) throws {
        let volume = "/Volumes/\(config.volumeName)"
        if !fileManager.fileExists(atPath: volume) {
            throw WuwaError("找不到外接硬碟：\(volume)")
        }
    }

    private func syncIfRealDirectory(_ source: String, label: String, config: WuwaConfig) throws -> String {
        if isSymlink(source) {
            return "⚠️ \(label) 已經是 symlink，略過同步"
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "⚠️ \(label) 不存在，略過同步"
        }

        let output = try runProcess("/usr/bin/rsync", arguments: ["-avh", source + "/", config.externalTarget + "/"])
        return "同步 \(label) 到外接硬碟\n\(output)\n✅ \(label) 已同步到 \(config.externalTarget)"
    }

    private func replaceWithSymlink(_ source: String, label: String, config: WuwaConfig) throws -> String {
        if isSymlink(source) {
            let currentTarget = try fileManager.destinationOfSymbolicLink(atPath: source)
            if currentTarget == config.externalTarget {
                return "✅ \(label) 已正確指向 \(config.externalTarget)"
            }
            try fileManager.removeItem(atPath: source)
            try fileManager.createSymbolicLink(atPath: source, withDestinationPath: config.externalTarget)
            return "⚠️ \(label) 是舊 symlink，已重建"
        }

        if fileManager.fileExists(atPath: source) {
            try fileManager.removeItem(atPath: source)
        }

        try fileManager.createSymbolicLink(atPath: source, withDestinationPath: config.externalTarget)
        return "✅ \(label) 已建立 symlink"
    }

    private func removeOneSymlink(_ source: String, label: String) throws -> String {
        let parent = (source as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)

        if isSymlink(source) {
            let target = try fileManager.destinationOfSymbolicLink(atPath: source)
            try fileManager.removeItem(atPath: source)
            try fileManager.createDirectory(atPath: source, withIntermediateDirectories: true)
            return "✅ \(label) 已移除 symlink，並重建空資料夾\n   原本指向：\(target)"
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: source, isDirectory: &isDirectory), isDirectory.boolValue {
            return "⚠️ \(label) 已經是實體資料夾，未變更"
        }

        if fileManager.fileExists(atPath: source) {
            return "⚠️ \(label) 是其他檔案，未變更"
        }

        try fileManager.createDirectory(atPath: source, withIntermediateDirectories: true)
        return "✅ \(label) 原本不存在，已建立空資料夾"
    }

    private func verifyPath(_ path: String, label: String, config: WuwaConfig) -> String {
        if isSymlink(path) {
            let target = (try? fileManager.destinationOfSymbolicLink(atPath: path)) ?? "<讀取失敗>"
            if target == config.externalTarget {
                return "✅ \(label) 正常 -> \(target)"
            }
            return "⚠️ \(label) 是 symlink，但指向 \(target)"
        }

        if fileManager.fileExists(atPath: path) {
            return "⚠️ \(label) 存在，但不是 symlink"
        }

        return "⚠️ \(label) 不存在"
    }

    private func pathStatus(_ path: String, label: String) -> PathStatus {
        if isSymlink(path) {
            let target = (try? fileManager.destinationOfSymbolicLink(atPath: path)) ?? "<讀取失敗>"
            return PathStatus(label: label, path: path, kind: "symlink", target: target)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return PathStatus(label: label, path: path, kind: "實體資料夾", target: nil)
        }

        if fileManager.fileExists(atPath: path) {
            return PathStatus(label: label, path: path, kind: "其他檔案", target: nil)
        }

        return PathStatus(label: label, path: path, kind: "不存在", target: nil)
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }
}

public func runProcess(_ launchPath: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let combined = [output, error].filter { !$0.isEmpty }.joined()

    if process.terminationStatus != 0 {
        throw WuwaError(combined.isEmpty ? "\(launchPath) 執行失敗，狀態碼 \(process.terminationStatus)" : combined)
    }

    return combined.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}
