import AppKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct AppearanceTests {
    @Test func choicesSurviveReopenAndExistingSavedValuesAreKept() throws {
        let domain = "local.luma.appearance-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        #expect(Workspace(preferences: preferences).appearance == .system)
        for choice in AppAppearance.allCases {
            // The string format remains compatible with previous releases.
            preferences.set(choice.rawValue, forKey: "appearance")
            let workspace = Workspace(preferences: preferences)
            #expect(workspace.appearance == choice)
            let next: AppAppearance = choice == .dark ? .system : .dark
            workspace.appearance = next
            #expect(Workspace(preferences: preferences).appearance == next)
        }
        preferences.set("invalid", forKey: "appearance")
        #expect(Workspace(preferences: preferences).appearance == .system)
    }

    final class Probe {
        var scheme: ColorScheme?
    }
    struct SchemeProbe: NSViewRepresentable {
        @Environment(\.colorScheme) private var colorScheme
        let probe: Probe
        func makeNSView(context: Context) -> NSView { NSView() }
        func updateNSView(_ view: NSView, context: Context) { probe.scheme = colorScheme }
    }
    struct Content: View {
        @Bindable var workspace: Workspace
        let tab: DocumentTab
        let probe: Probe
        var body: some View {
            VStack {
                AppearancePicker(selection: $workspace.appearance).pickerStyle(.segmented)
                SourceView(text: tab.draft ?? "", tab: tab)
                SchemeProbe(probe: probe).frame(height: 1)
            }
            .frame(width: 400, height: 300)
            .preferredColorScheme(workspace.appearance.colorScheme)
        }
    }

    @Test func liveSwitchUpdatesSwiftUIAndNativeEditorWithoutLosingDraftOrSelection() async throws {
        _ = NSApplication.shared
        let domain = "local.luma.appearance-live.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/appearance.txt"))
        tab.edit("草稿保持不变")
        let probe = Probe()
        let controller = NSHostingController(rootView: Content(workspace: workspace, tab: tab, probe: probe))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let editor = tab.sourceEditor()
        editor.textView.setSelectedRange(NSRange(location: 1, length: 2))
        let undo = editor.textView.undoManager
        for choice in [AppAppearance.dark, .light, .system] {
            workspace.appearance = choice
            let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let expected: ColorScheme = choice.colorScheme ?? (systemDark ? .dark : .light)
            let deadline = ContinuousClock.now + .seconds(2)
            while probe.scheme != expected && ContinuousClock.now < deadline {
                controller.view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(probe.scheme == expected)
            #expect(editor.textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == (expected == .dark ? .darkAqua : .aqua))
            #expect(editor.textView.string == "草稿保持不变" && tab.isDirty)
            #expect(editor.textView.selectedRange() == NSRange(location: 1, length: 2))
            #expect(editor.textView.undoManager === undo)
        }
    }
}
