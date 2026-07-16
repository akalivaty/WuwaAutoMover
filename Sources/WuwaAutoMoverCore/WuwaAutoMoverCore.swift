import Foundation

public enum WuwaLanguage: String, Sendable {
    case english
    case traditionalChinese

    public func text(_ english: String, _ traditionalChinese: String) -> String {
        switch self {
        case .english: english
        case .traditionalChinese: traditionalChinese
        }
    }
}

public struct WuwaStoredSettings: Codable, Sendable {
    public var version: String
    public var volumeName: String
    public var externalRoot: String
    public var appContainerID: String
    public var appPath: String

    public init(
        version: String = "",
        volumeName: String = "",
        externalRoot: String = "",
        appContainerID: String = "",
        appPath: String = ""
    ) {
        self.version = version
        self.volumeName = volumeName
        self.externalRoot = externalRoot
        self.appContainerID = appContainerID
        self.appPath = appPath
    }
}

public struct WuwaPlaceholders: Sendable {
    public static let version = "3.4.0"
    public static let volumeName = "T7"
    public static let externalRoot = "WuwaData"
    public static let appContainerID = "com.kurogame.wutheringwaves.global"
    public static let appPath = "/Volumes/T7/Applications/WutheringWaves.app"
}

public final class WuwaSettingsStore: @unchecked Sendable {
    private let fileManager: FileManager
    public let configURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.configURL = appSupport.appendingPathComponent("WuwaAutoMover/config.json")
    }

    public func load() -> WuwaStoredSettings {
        guard let data = try? Data(contentsOf: configURL),
              let settings = try? JSONDecoder().decode(WuwaStoredSettings.self, from: data)
        else {
            return WuwaStoredSettings()
        }
        return settings
    }

    public func save(_ settings: WuwaStoredSettings) throws {
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: configURL, options: [.atomic])
    }
}

public struct WuwaConfig: Sendable {
    public let version: String
    public let volumeName: String
    public let externalRoot: String
    public let appContainerID: String
    public let appPath: String

    public init(
        version: String,
        volumeName: String,
        externalRoot: String,
        appContainerID: String,
        appPath: String,
        language: WuwaLanguage = .traditionalChinese
    ) throws {
        try WuwaConfig.validatePathComponent(
            version,
            name: language.text("Resource version", "版本號"),
            language: language
        )
        try WuwaConfig.validatePathComponent(
            volumeName,
            name: language.text("External volume name", "外接硬碟名稱"),
            language: language
        )
        try WuwaConfig.validateRelativePath(
            externalRoot,
            name: language.text("External folder", "外接資料夾"),
            language: language
        )
        try WuwaConfig.validatePathComponent(appContainerID, name: "App container ID", language: language)
        if appPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !appPath.hasPrefix("/") {
            throw WuwaError(language.text(
                "WutheringWaves.app must use an absolute path.",
                "WutheringWaves.app 必須是絕對路徑。"
            ))
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

    public var externalClient: String {
        "/Volumes/\(volumeName)/\(externalRoot)/Client"
    }

    public var source1Base: String {
        "\(NSHomeDirectory())/Library/Containers/\(appContainerID)/Data/Library/Client/Saved/Resources"
    }

    public var source2Base: String {
        "\(NSHomeDirectory())/Library/Client/Saved/Resources"
    }

    public var userClient: String {
        "\(NSHomeDirectory())/Library/Client"
    }

    public var source1: String {
        "\(source1Base)/\(version)"
    }

    public var storedSettings: WuwaStoredSettings {
        WuwaStoredSettings(
            version: version,
            volumeName: volumeName,
            externalRoot: externalRoot,
            appContainerID: appContainerID,
            appPath: appPath
        )
    }

    public var source2: String {
        "\(source2Base)/\(version)"
    }

    private static func validatePathComponent(_ value: String, name: String, language: WuwaLanguage) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WuwaError(language.text("\(name) cannot be empty.", "\(name) 不能空白。"))
        }
        if value.contains("/") || value == "." || value == ".." {
            throw WuwaError(language.text(
                "\(name) cannot contain slashes or special path components.",
                "\(name) 不能包含斜線或特殊路徑。"
            ))
        }
    }

    private static func validateRelativePath(_ value: String, name: String, language: WuwaLanguage) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WuwaError(language.text("\(name) cannot be empty.", "\(name) 不能空白。"))
        }
        if value.hasPrefix("/") || value.split(separator: "/").contains("..") {
            throw WuwaError(language.text(
                "\(name) must be a relative path under the external volume.",
                "\(name) 必須是外接硬碟底下的相對路徑。"
            ))
        }
    }
}

public struct PathStatus: Sendable {
    public let label: String
    public let path: String
    public let kind: String
    public let target: String?
}

public struct ResourceCleanupEntry: Sendable, Hashable {
    public let locationLabel: String
    public let resourceDirectory: String
    public let name: String
    public let symbolicLinkTarget: String?

    public var path: String {
        (resourceDirectory as NSString).appendingPathComponent(name)
    }

    init(
        locationLabel: String,
        resourceDirectory: String,
        name: String,
        symbolicLinkTarget: String?
    ) {
        self.locationLabel = locationLabel
        self.resourceDirectory = resourceDirectory
        self.name = name
        self.symbolicLinkTarget = symbolicLinkTarget
    }
}

public struct WuwaStatus: Sendable {
    public let config: WuwaConfig
    public let volumeExists: Bool
    public let externalTargetExists: Bool
    public let externalTargetSize: String?
    public let externalClientExists: Bool
    public let sandboxEntitlementPresent: Bool?
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
    private let language: WuwaLanguage

    public init(fileManager: FileManager = .default, language: WuwaLanguage = .traditionalChinese) {
        self.fileManager = fileManager
        self.language = language
    }

    private func t(_ english: String, _ traditionalChinese: String) -> String {
        language.text(english, traditionalChinese)
    }

    public func status(config: WuwaConfig) -> WuwaStatus {
        let volumeExists = fileManager.fileExists(atPath: "/Volumes/\(config.volumeName)")
        let externalTargetExists = fileManager.fileExists(atPath: config.externalTarget)
        let size = externalTargetExists ? try? runProcess("/usr/bin/du", arguments: ["-sh", config.externalTarget], language: language) : nil
        let entitlements = try? inspectEntitlements(config: config)
        return WuwaStatus(
            config: config,
            volumeExists: volumeExists,
            externalTargetExists: externalTargetExists,
            externalTargetSize: size?.trimmingCharacters(in: .whitespacesAndNewlines),
            externalClientExists: fileManager.fileExists(atPath: config.externalClient),
            sandboxEntitlementPresent: entitlements?.contains("com.apple.security.app-sandbox"),
            entries: [
                pathStatus(config.source1, label: t("Container path", "Container 路徑")),
                pathStatus(config.source2, label: t("User Library resource-version path", "使用者 Library 資源版本路徑")),
                pathStatus(config.userClient, label: t("User Library Client path", "使用者 Library Client 路徑"))
            ]
        )
    }

    public func staleResourceEntries(config: WuwaConfig) throws -> [ResourceCleanupEntry] {
        try staleResourceEntries(
            currentVersion: config.version,
            resourceDirectories: [
                (label: "Container Resources", path: config.source1Base),
                (label: t("User Library Resources", "使用者 Library Resources"), path: config.source2Base)
            ]
        )
    }

    public func removeStaleResourceEntries(
        _ entries: [ResourceCleanupEntry],
        config: WuwaConfig
    ) throws -> OperationResult {
        try removeStaleResourceEntries(
            entries,
            currentVersion: config.version,
            allowedResourceDirectories: [config.source1Base, config.source2Base],
            allowedSymlinkTargetDirectories: [config.externalBase],
            language: language
        )
    }

    func staleResourceEntries(
        currentVersion: String,
        resourceDirectories: [(label: String, path: String)]
    ) throws -> [ResourceCleanupEntry] {
        var entries: [ResourceCleanupEntry] = []

        for directory in resourceDirectories {
            let standardizedDirectory = (directory.path as NSString).standardizingPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedDirectory, isDirectory: &isDirectory) else {
                continue
            }
            guard isDirectory.boolValue else {
                throw WuwaError(t(
                    "Resources path is not a directory: \(standardizedDirectory)",
                    "Resources 路徑不是資料夾：\(standardizedDirectory)"
                ))
            }

            let names: [String]
            do {
                names = try fileManager.contentsOfDirectory(atPath: standardizedDirectory)
            } catch {
                throw WuwaError(t(
                    "Cannot read Resources path: \(standardizedDirectory)\n\(error.localizedDescription)",
                    "無法讀取 Resources 路徑：\(standardizedDirectory)\n\(error.localizedDescription)"
                ))
            }

            entries.append(contentsOf: names
                .filter { !$0.hasPrefix(".") && $0 != currentVersion }
                .map {
                    let path = (standardizedDirectory as NSString).appendingPathComponent($0)
                    return ResourceCleanupEntry(
                        locationLabel: directory.label,
                        resourceDirectory: standardizedDirectory,
                        name: $0,
                        symbolicLinkTarget: resolvedSymbolicLinkTarget(atPath: path)
                    )
                })
        }

        return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func removeStaleResourceEntries(
        _ entries: [ResourceCleanupEntry],
        currentVersion: String,
        allowedResourceDirectories: [String],
        allowedSymlinkTargetDirectories: [String],
        language operationLanguage: WuwaLanguage? = nil
    ) throws -> OperationResult {
        let language = operationLanguage ?? self.language
        func localize(_ english: String, _ traditionalChinese: String) -> String {
            language.text(english, traditionalChinese)
        }
        let allowedDirectories = Set(allowedResourceDirectories.map { ($0 as NSString).standardizingPath })
        let allowedTargetDirectories = Set(allowedSymlinkTargetDirectories.map { ($0 as NSString).standardizingPath })

        let deletionPlans: [(path: String, target: String?)] = try entries.map { entry in
            let resourceDirectory = (entry.resourceDirectory as NSString).standardizingPath
            guard allowedDirectories.contains(resourceDirectory),
                  entry.name != currentVersion,
                  !entry.name.isEmpty,
                  !entry.name.hasPrefix("."),
                  !entry.name.contains("/"),
                  entry.name != ".",
                  entry.name != ".."
            else {
                throw WuwaError(localize(
                    "Refusing to delete an unsafe resource path: \(entry.path)",
                    "拒絕刪除不安全的資源路徑：\(entry.path)"
                ))
            }

            let path = (resourceDirectory as NSString).appendingPathComponent(entry.name)
            if let expectedTarget = entry.symbolicLinkTarget {
                let standardizedTarget = (expectedTarget as NSString).standardizingPath
                let targetDirectory = (standardizedTarget as NSString).deletingLastPathComponent
                let targetName = (standardizedTarget as NSString).lastPathComponent
                guard allowedTargetDirectories.contains(targetDirectory), targetName == entry.name else {
                    throw WuwaError(localize(
                        "Refusing to delete a symlink target outside the configured resources: \(standardizedTarget)",
                        "拒絕刪除設定之外的 symlink 目標：\(standardizedTarget)"
                    ))
                }

                guard resolvedSymbolicLinkTarget(atPath: path) == standardizedTarget else {
                    throw WuwaError(localize(
                        "The symlink target changed after confirmation; deletion stopped: \(path)",
                        "symlink 目標在確認後已變更，已停止刪除：\(path)"
                    ))
                }

                return (path: path, target: standardizedTarget)
            }
            return (path: path, target: nil)
        }

        var lines = [localize("Clean up other resource versions", "清理其他版本資源")]
        for plan in deletionPlans {
            if let target = plan.target {
                if fileManager.fileExists(atPath: target) || isSymlink(target) {
                    do {
                        try fileManager.removeItem(atPath: target)
                        lines.append(localize(
                            "Deleted data targeted by symlink: \(target)",
                            "已刪除 symlink 指向的實際資料：\(target)"
                        ))
                    } catch {
                        throw WuwaError(localize(
                            "Cannot delete data targeted by symlink: \(target)\n\(error.localizedDescription)",
                            "無法刪除 symlink 指向的實際資料：\(target)\n\(error.localizedDescription)"
                        ))
                    }
                } else {
                    lines.append(localize(
                        "Symlink target data no longer exists: \(target)",
                        "symlink 指向的實際資料已不存在：\(target)"
                    ))
                }
            }

            guard fileManager.fileExists(atPath: plan.path) || isSymlink(plan.path) else {
                lines.append(localize("Item no longer exists: \(plan.path)", "項目已不存在：\(plan.path)"))
                continue
            }

            do {
                try fileManager.removeItem(atPath: plan.path)
                lines.append(localize("Deleted: \(plan.path)", "已刪除：\(plan.path)"))
            } catch {
                throw WuwaError(localize(
                    "Cannot delete resource: \(plan.path)\n\(error.localizedDescription)",
                    "無法刪除資源：\(plan.path)\n\(error.localizedDescription)"
                ))
            }
        }

        if entries.isEmpty {
            lines.append(localize(
                "No other resource versions need to be deleted.",
                "沒有需要刪除的其他版本資源。"
            ))
        }
        return OperationResult(lines)
    }

    public func createRecommendedSetup(config: WuwaConfig, administratorPrivileges: Bool) throws -> OperationResult {
        var lines: [String] = []
        lines.append(t(
            "Option 1: Codesign first, then link the user Library resource-version folder",
            "選項 1：先 Codesign，再連結使用者 Library 資源版本資料夾"
        ))
        lines.append(try codesignApp(config: config, administratorPrivileges: administratorPrivileges).text)
        lines.append(try createUserResourceVersionSymlink(config: config).text)
        lines.append(t(
            "Option 1 completed. The container path usually needs no further changes.",
            "選項 1 完成。通常不需要再處理 container 路徑。"
        ))
        return OperationResult(lines)
    }

    public func createUserResourceVersionSymlink(config: WuwaConfig) throws -> OperationResult {
        try ensureVolumeExists(config)

        var lines: [String] = []
        lines.append(t("Create required folders", "建立必要資料夾"))
        try fileManager.createDirectory(atPath: config.externalTarget, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: config.source2Base, withIntermediateDirectories: true)
        lines.append(t(
            "External version folder is ready: \(config.externalTarget)",
            "外接版本資料夾已準備完成：\(config.externalTarget)"
        ))
        lines.append(t(
            "User Library Resources folder is ready: \(config.source2Base)",
            "使用者 Library Resources 資料夾已準備完成：\(config.source2Base)"
        ))

        let userResourceLabel = t("User Library resource-version path", "使用者 Library 資源版本路徑")
        lines.append(try syncIfRealDirectory(config.source2, label: userResourceLabel, destination: config.externalTarget))
        lines.append(try replaceWithSymlink(config.source2, label: userResourceLabel, destination: config.externalTarget))

        lines.append("")
        lines.append(t("Verification", "驗證結果"))
        lines.append(verifyPath(config.source2, label: userResourceLabel, expectedTarget: config.externalTarget))
        lines.append(t("Completed. You can now open the game and test it.", "完成。現在可以開遊戲測試。"))
        return OperationResult(lines)
    }

    public func createClientSymlink(config: WuwaConfig) throws -> OperationResult {
        try ensureVolumeExists(config)

        var lines: [String] = []
        lines.append(t(
            "Option 2: Make the entire ~/Library/Client a symlink",
            "選項 2：把整個 ~/Library/Client 做成 symlink"
        ))
        try fileManager.createDirectory(atPath: config.externalClient, withIntermediateDirectories: true)
        lines.append(t(
            "External Client folder is ready: \(config.externalClient)",
            "外接 Client 資料夾已準備完成：\(config.externalClient)"
        ))

        if isSymlink(config.userClient) {
            let currentTarget = try fileManager.destinationOfSymbolicLink(atPath: config.userClient)
            if currentTarget == config.externalClient {
                lines.append(t(
                    "~/Library/Client already points to \(config.externalClient)",
                    "~/Library/Client 已正確指向 \(config.externalClient)"
                ))
                return OperationResult(lines)
            }
            try fileManager.removeItem(atPath: config.userClient)
            try fileManager.createSymbolicLink(atPath: config.userClient, withDestinationPath: config.externalClient)
            lines.append(t(
                "~/Library/Client was an outdated symlink and has been rebuilt.",
                "~/Library/Client 是舊 symlink，已重建"
            ))
            return OperationResult(lines)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: config.userClient, isDirectory: &isDirectory), isDirectory.boolValue {
            lines.append(try syncDirectory(config.userClient, destination: config.externalClient, label: "~/Library/Client"))
            let backup = backupPath(for: config.userClient)
            try fileManager.moveItem(atPath: config.userClient, toPath: backup)
            lines.append(t(
                "The original ~/Library/Client was moved to backup: \(backup)",
                "原本的 ~/Library/Client 已搬到備份：\(backup)"
            ))
        } else if fileManager.fileExists(atPath: config.userClient) {
            throw WuwaError(t(
                "~/Library/Client exists but is not a folder or symlink. Handle it manually first: \(config.userClient)",
                "~/Library/Client 存在但不是資料夾或 symlink，請先手動處理：\(config.userClient)"
            ))
        }

        let parent = (config.userClient as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: config.userClient, withDestinationPath: config.externalClient)
        lines.append(t(
            "Created ~/Library/Client symlink -> \(config.externalClient)",
            "~/Library/Client 已建立 symlink -> \(config.externalClient)"
        ))
        return OperationResult(lines)
    }

    public func createConservativeFallbackSymlinks(config: WuwaConfig) throws -> OperationResult {
        try ensureVolumeExists(config)

        var lines: [String] = []
        lines.append(t(
            "Option 3: Conservative fallback for both container and user Library paths",
            "選項 3：最保守備援方法，同時處理 container 與使用者 Library 路徑"
        ))
        lines.append(t("Create required folders", "建立必要資料夾"))
        try fileManager.createDirectory(atPath: config.externalTarget, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: config.source1Base, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: config.source2Base, withIntermediateDirectories: true)
        lines.append(t("External destination is ready.", "外接目標資料夾已準備完成"))

        let containerLabel = t("Container path", "Container 路徑")
        let userResourceLabel = t("User Library resource-version path", "使用者 Library 資源版本路徑")
        lines.append(try syncIfRealDirectory(config.source1, label: containerLabel, destination: config.externalTarget))
        lines.append(try syncIfRealDirectory(config.source2, label: userResourceLabel, destination: config.externalTarget))
        lines.append(try replaceWithSymlink(config.source1, label: containerLabel, destination: config.externalTarget))
        lines.append(try replaceWithSymlink(config.source2, label: userResourceLabel, destination: config.externalTarget))

        lines.append("")
        lines.append(t("Verification", "驗證結果"))
        lines.append(verifyPath(config.source1, label: containerLabel, expectedTarget: config.externalTarget))
        lines.append(verifyPath(config.source2, label: userResourceLabel, expectedTarget: config.externalTarget))
        lines.append(t("Completed. You can now open the game and test it.", "完成。現在可以開遊戲測試。"))
        return OperationResult(lines)
    }

    public func createOrUpdateSymlinks(config: WuwaConfig) throws -> OperationResult {
        try createConservativeFallbackSymlinks(config: config)
    }

    public func removeSymlinks(config: WuwaConfig) throws -> OperationResult {
        OperationResult([
            try removeOneSymlink(config.source1, label: t("Container path", "Container 路徑")),
            try removeOneSymlink(config.source2, label: t("User Library path", "使用者 Library 路徑")),
            t(
                "Symlinks were removed. Data on the external disk was not deleted.",
                "symlink 已移除。外接硬碟上的資料未刪除。"
            )
        ])
    }

    public func codesignApp(config: WuwaConfig, administratorPrivileges: Bool) throws -> OperationResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: config.appPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WuwaError(t(
                "WutheringWaves.app was not found: \(config.appPath)",
                "找不到 WutheringWaves.app：\(config.appPath)"
            ))
        }

        let arguments = ["--sign", "-", "--force", "--deep", config.appPath]
        do {
            let output = try runProcess("/usr/bin/codesign", arguments: arguments, language: language)
            return OperationResult([t("Codesign completed.", "codesign 已完成。"), output].filter { !$0.isEmpty })
        } catch {
            let directError = error.localizedDescription
            guard administratorPrivileges else { throw error }

            let command = "/usr/bin/codesign --sign - --force --deep \(shellQuote(config.appPath))"
            let script = "do shell script \(appleScriptString(command)) with administrator privileges"
            do {
                let output = try runProcess("/usr/bin/osascript", arguments: ["-e", script], language: language)
                return OperationResult([
                    t("Codesign completed with administrator privileges.", "codesign 已使用管理員權限完成。"),
                    output
                ].filter { !$0.isEmpty })
            } catch {
                throw WuwaError(t(
                    """
                    Codesign failed.

                    Direct signing:
                    \(directError)

                    Administrator signing:
                    \(error.localizedDescription)

                    Select WutheringWaves.app again, confirm that the external disk is connected, and retry.
                    """,
                    """
                    codesign 失敗。

                    直接簽署：
                    \(directError)

                    管理員簽署：
                    \(error.localizedDescription)

                    請重新選擇 WutheringWaves.app，確認外接磁碟仍已連接後再試。
                    """
                ))
            }
        }
    }

    public func inspectEntitlements(config: WuwaConfig) throws -> String {
        try runProcess(
            "/usr/bin/codesign",
            arguments: ["-d", "--entitlements", ":-", config.appPath],
            language: language
        )
    }

    public func describe(status: WuwaStatus) -> String {
        var lines: [String] = []
        lines.append(t("Version: \(status.config.version)", "版本號：\(status.config.version)"))
        lines.append(t("External destination: \(status.config.externalTarget)", "外接目標：\(status.config.externalTarget)"))
        lines.append(t("External Client: \(status.config.externalClient)", "外接 Client：\(status.config.externalClient)"))
        lines.append(status.volumeExists
            ? t("External disk found: /Volumes/\(status.config.volumeName)", "已找到外接硬碟：/Volumes/\(status.config.volumeName)")
            : t("External disk not found: /Volumes/\(status.config.volumeName)", "找不到外接硬碟：/Volumes/\(status.config.volumeName)"))
        lines.append(status.externalTargetExists
            ? t("External destination exists", "外接目標存在")
            : t("External destination does not exist", "外接目標不存在"))
        lines.append(status.externalClientExists
            ? t("External Client exists", "外接 Client 存在")
            : t("External Client does not exist", "外接 Client 不存在"))
        if let sandboxEntitlementPresent = status.sandboxEntitlementPresent {
            lines.append(sandboxEntitlementPresent
                ? t("App sandbox entitlement is still present", "app sandbox entitlement 仍然存在")
                : t("App sandbox entitlement is absent", "app sandbox entitlement 不存在"))
        } else {
            lines.append(t("Unable to inspect app entitlements", "無法檢查 app entitlements"))
        }
        if let size = status.externalTargetSize {
            lines.append(t("External destination size: \(size)", "外接目標容量：\(size)"))
        }
        for entry in status.entries {
            lines.append("")
            lines.append("[\(entry.label)]")
            lines.append(t("Path: \(entry.path)", "路徑：\(entry.path)"))
            lines.append(t("Type: \(entry.kind)", "類型：\(entry.kind)"))
            if let target = entry.target {
                lines.append(t("Target: \(target)", "指向：\(target)"))
            }
        }
        return lines.joined(separator: "\n")
    }

    private func ensureVolumeExists(_ config: WuwaConfig) throws {
        let volume = "/Volumes/\(config.volumeName)"
        if !fileManager.fileExists(atPath: volume) {
            throw WuwaError(t("External disk not found: \(volume)", "找不到外接硬碟：\(volume)"))
        }
    }

    private func syncIfRealDirectory(_ source: String, label: String, destination: String) throws -> String {
        if isSymlink(source) {
            return t("\(label) is already a symlink; skipping sync.", "\(label) 已經是 symlink，略過同步")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source, isDirectory: &isDirectory), isDirectory.boolValue else {
            return t("\(label) does not exist; skipping sync.", "\(label) 不存在，略過同步")
        }

        return try syncDirectory(source, destination: destination, label: label)
    }

    private func syncDirectory(_ source: String, destination: String, label: String) throws -> String {
        let output = try runProcess(
            "/usr/bin/rsync",
            arguments: ["-avh", source + "/", destination + "/"],
            language: language
        )
        return t(
            "Sync \(label) to the external disk\n\(output)\n\(label) was synced to \(destination)",
            "同步 \(label) 到外接硬碟\n\(output)\n\(label) 已同步到 \(destination)"
        )
    }

    private func replaceWithSymlink(_ source: String, label: String, destination: String) throws -> String {
        if isSymlink(source) {
            let currentTarget = try fileManager.destinationOfSymbolicLink(atPath: source)
            if currentTarget == destination {
                return t("\(label) already points to \(destination)", "\(label) 已正確指向 \(destination)")
            }
            try fileManager.removeItem(atPath: source)
            try fileManager.createSymbolicLink(atPath: source, withDestinationPath: destination)
            return t("\(label) was an outdated symlink and has been rebuilt.", "\(label) 是舊 symlink，已重建")
        }

        if fileManager.fileExists(atPath: source) {
            try fileManager.removeItem(atPath: source)
        }

        let parent = (source as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: source, withDestinationPath: destination)
        return t("Created symlink for \(label)", "\(label) 已建立 symlink")
    }

    private func removeOneSymlink(_ source: String, label: String) throws -> String {
        let parent = (source as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)

        if isSymlink(source) {
            let target = try fileManager.destinationOfSymbolicLink(atPath: source)
            try fileManager.removeItem(atPath: source)
            try fileManager.createDirectory(atPath: source, withIntermediateDirectories: true)
            return t(
                "Removed symlink for \(label) and created an empty folder\n   Previous target: \(target)",
                "\(label) 已移除 symlink，並重建空資料夾\n   原本指向：\(target)"
            )
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: source, isDirectory: &isDirectory), isDirectory.boolValue {
            return t("\(label) is already a real folder; no changes made.", "\(label) 已經是實體資料夾，未變更")
        }

        if fileManager.fileExists(atPath: source) {
            return t("\(label) is another file type; no changes made.", "\(label) 是其他檔案，未變更")
        }

        try fileManager.createDirectory(atPath: source, withIntermediateDirectories: true)
        return t("\(label) did not exist; created an empty folder.", "\(label) 原本不存在，已建立空資料夾")
    }

    private func verifyPath(_ path: String, label: String, expectedTarget: String) -> String {
        if isSymlink(path) {
            let target = (try? fileManager.destinationOfSymbolicLink(atPath: path))
                ?? t("<read failed>", "<讀取失敗>")
            if target == expectedTarget {
                return t("\(label) is correct -> \(target)", "\(label) 正常 -> \(target)")
            }
            return t("\(label) is a symlink pointing to \(target)", "\(label) 是 symlink，但指向 \(target)")
        }

        if fileManager.fileExists(atPath: path) {
            return t("\(label) exists but is not a symlink.", "\(label) 存在，但不是 symlink")
        }

        return t("\(label) does not exist.", "\(label) 不存在")
    }

    private func pathStatus(_ path: String, label: String) -> PathStatus {
        if isSymlink(path) {
            let target = (try? fileManager.destinationOfSymbolicLink(atPath: path))
                ?? t("<read failed>", "<讀取失敗>")
            return PathStatus(label: label, path: path, kind: "symlink", target: target)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return PathStatus(label: label, path: path, kind: t("real folder", "實體資料夾"), target: nil)
        }

        if fileManager.fileExists(atPath: path) {
            return PathStatus(label: label, path: path, kind: t("other file", "其他檔案"), target: nil)
        }

        return PathStatus(label: label, path: path, kind: t("missing", "不存在"), target: nil)
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func resolvedSymbolicLinkTarget(atPath path: String) -> String? {
        guard let target = try? fileManager.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }
        if target.hasPrefix("/") {
            return (target as NSString).standardizingPath
        }
        let parent = (path as NSString).deletingLastPathComponent
        return ((parent as NSString).appendingPathComponent(target) as NSString).standardizingPath
    }

    private func backupPath(for path: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(path).old.\(formatter.string(from: Date()))"
    }
}

public func runProcess(
    _ launchPath: String,
    arguments: [String],
    language: WuwaLanguage = .traditionalChinese
) throws -> String {
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
        throw WuwaError(combined.isEmpty
            ? language.text(
                "\(launchPath) failed with status \(process.terminationStatus)",
                "\(launchPath) 執行失敗，狀態碼 \(process.terminationStatus)"
            )
            : combined)
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
