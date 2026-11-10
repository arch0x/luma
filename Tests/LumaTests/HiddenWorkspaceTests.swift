import Foundation
import Testing
@testable import Luma

@MainActor struct HiddenWorkspaceTests {
    @Test func hiddenFoldersExpandAndNewHiddenFilesAreVisibleAndSearchable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let domain = "local.luma.hidden-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: directory); preferences.removePersistentDomain(forName: domain) }
        let folder = directory.appendingPathComponent(".config", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try "hidden".write(to: folder.appendingPathComponent("needle.txt"), atomically: true, encoding: .utf8)
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.roots = [directory]
        workspace.loadDirectory(directory)
        let deadline = ContinuousClock.now + .seconds(5)
        while !workspace.loadingDirectories.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let entry = try #require(workspace.directories[directory]?.first { $0.name == ".config" })
        workspace.toggleDirectory(entry.url)
        while !workspace.loadingDirectories.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(workspace.directories[entry.url]?.first?.name == "needle.txt")
        _ = try await workspace.createFile(named: ".env", in: directory)
        await workspace.activeTab?.loadTask?.value
        while !workspace.loadingDirectories.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(workspace.directories[directory]?.contains { $0.name == ".env" } == true)
        let nested = try await workspace.files.search("needle", roots: [directory])
        #expect(nested.contains { $0.url.path.contains("/.config/") })
        let hidden = try await workspace.files.search(".env", roots: [directory])
        #expect(hidden.map(\.name) == [".env"])
    }
}
