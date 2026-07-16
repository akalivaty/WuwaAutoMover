import Foundation
import XCTest
@testable import WuwaAutoMoverCore

final class WuwaAutoMoverCoreTests: XCTestCase {
    func testCodesignAppSignsBundleDirectlyWithoutAdministratorPrompt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("TestGame.app")
        let contents = app.appendingPathComponent("Contents")
        let executableDirectory = contents.appendingPathComponent("MacOS")
        let executable = executableDirectory.appendingPathComponent("TestGame")
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let plist: [String: Any] = [
            "CFBundleExecutable": "TestGame",
            "CFBundleIdentifier": "com.example.WuwaAutoMoverCodesignTest",
            "CFBundleName": "TestGame",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let config = try WuwaConfig(
            version: "3.4.0",
            volumeName: "TestVolume",
            externalRoot: "WuwaData",
            appContainerID: "com.example.test",
            appPath: app.path
        )
        let result = try WuwaMover(language: .english).codesignApp(
            config: config,
            administratorPrivileges: false
        )

        XCTAssertTrue(result.text.contains("Codesign completed"))
        _ = try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", app.path])
    }

    func testEnglishValidationError() throws {
        XCTAssertThrowsError(try WuwaConfig(
            version: "",
            volumeName: "TestVolume",
            externalRoot: "WuwaData",
            appContainerID: "com.example.test",
            appPath: "/Applications/WutheringWaves.app",
            language: .english
        )) { error in
            XCTAssertEqual(error.localizedDescription, "Resource version cannot be empty.")
        }
    }

    func testStaleResourceEntriesKeepCurrentVersionAndSkipHiddenFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let container = root.appendingPathComponent("ContainerResources")
        let user = root.appendingPathComponent("UserResources")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: container.appendingPathComponent("3.4.0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: container.appendingPathComponent("3.5.0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: user.appendingPathComponent("Video"), withIntermediateDirectories: true)
        try Data().write(to: user.appendingPathComponent(".DS_Store"))

        let entries = try WuwaMover().staleResourceEntries(
            currentVersion: "3.4.0",
            resourceDirectories: [
                (label: "Container", path: container.path),
                (label: "User", path: user.path)
            ]
        )

        XCTAssertEqual(Set(entries.map(\.name)), ["3.5.0", "Video"])
        XCTAssertFalse(entries.contains { $0.name == "3.4.0" })
        XCTAssertFalse(entries.contains { $0.name == ".DS_Store" })
    }

    func testRemoveStaleResourceEntriesDeletesSymlinkAndTargetData() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appendingPathComponent("Resources")
        let externalResources = root.appendingPathComponent("ExternalResources")
        let symlinkTarget = externalResources.appendingPathComponent("3.3.0")
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("3.4.0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Video"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlinkTarget, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: symlinkTarget.appendingPathComponent("data.bin"))
        try FileManager.default.createSymbolicLink(
            at: resources.appendingPathComponent("3.3.0"),
            withDestinationURL: symlinkTarget
        )

        let mover = WuwaMover()
        let entries = try mover.staleResourceEntries(
            currentVersion: "3.4.0",
            resourceDirectories: [(label: "Resources", path: resources.path)]
        )
        _ = try mover.removeStaleResourceEntries(
            entries,
            currentVersion: "3.4.0",
            allowedResourceDirectories: [resources.path],
            allowedSymlinkTargetDirectories: [externalResources.path]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appendingPathComponent("3.4.0").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resources.appendingPathComponent("Video").path))
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: resources.appendingPathComponent("3.3.0").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkTarget.path))
    }

    func testRemoveStaleResourceEntriesRejectsTargetOutsideConfiguredExternalResources() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appendingPathComponent("Resources")
        let allowedExternalResources = root.appendingPathComponent("AllowedExternalResources")
        let unrelatedTarget = root.appendingPathComponent("Unrelated/3.3.0")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: allowedExternalResources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelatedTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: resources.appendingPathComponent("3.3.0"),
            withDestinationURL: unrelatedTarget
        )

        let mover = WuwaMover()
        let entries = try mover.staleResourceEntries(
            currentVersion: "3.4.0",
            resourceDirectories: [(label: "Resources", path: resources.path)]
        )

        XCTAssertThrowsError(try mover.removeStaleResourceEntries(
            entries,
            currentVersion: "3.4.0",
            allowedResourceDirectories: [resources.path],
            allowedSymlinkTargetDirectories: [allowedExternalResources.path]
        ))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: resources.appendingPathComponent("3.3.0").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedTarget.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WuwaAutoMoverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
