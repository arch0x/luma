import AppKit
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct WindowCloseTests {
    final class OriginalDelegate: NSObject, NSWindowDelegate {
        var allowed = true
        var questions = 0
        var closed = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool { questions += 1; return allowed }
        func windowWillClose(_ notification: Notification) { closed += 1 }
    }

    @Test(arguments: [true, false])
    func windowCloseHonorsCancelSaveAndOriginalDelegateVeto(originalAllows: Bool) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.window-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        defer {
            preferences.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: file)
        }
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        tab.edit("draft")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let original = OriginalDelegate()
        original.allowed = originalAllows
        window.delegate = original
        let attachment = WorkspaceWindowBridge.WindowAttachment(workspace: workspace)
        window.contentView = attachment
        let guardDelegate = attachment.guardDelegate
        #expect(window.delegate === guardDelegate)
        workspace.chooseUnsaved = { _ in .cancel }
        #expect(guardDelegate.windowShouldClose(window) == false)
        await guardDelegate.closeTask?.value
        #expect(tab.isDirty && original.closed == 0 && original.questions == 0)
        workspace.chooseUnsaved = { _ in originalAllows ? .save : .discard }
        #expect(guardDelegate.windowShouldClose(window) == false)
        await guardDelegate.closeTask?.value
        #expect(original.questions == 1)
        #expect(original.closed == (originalAllows ? 1 : 0))
        #expect(tab.isDirty == !originalAllows)
        #expect(try String(contentsOf: file, encoding: .utf8) == (originalAllows ? "draft" : "original"))
        window.delegate = nil
        window.close()
    }
}
