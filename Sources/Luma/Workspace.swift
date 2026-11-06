import AppKit
import Observation
import ReaderCore

enum LoadedContent {
    case text(String)
    case markdown(String)
    case json(String, JSONNode)
    case table(String, CSVDocument)
    case native
    case failed(String)

    var source: String? {
        switch self {
        case .text(let text), .markdown(let text), .json(let text, _), .table(let text, _): text
        default: nil
        }
    }
}

enum LoadState {
    case loading
    case ready(LoadedContent)
}

@Observable final class DocumentTab: Identifiable {
    private(set) var url: URL
    private(set) var kind: DocumentKind
    var id: URL { url }
    var title: String { url.lastPathComponent }
    var state = LoadState.loading
    var showSource = false
    var textOffset: CGFloat = 0
    var markdownOffset = 0.0
    var markdownLocation: MarkdownReadingLocation?
    private(set) var readingSession: MarkdownReadingSession?
    var markdownBookmarkRequest = 0
    var markdownBookmarkHandledRequest = 0
    @ObservationIgnored var markdownCaptureID: UUID?
    @ObservationIgnored var captureMarkdownPosition: (() async -> Void)?
    var markdownOutlineVisible: Bool?
    var markdownCollapsedHeadings: Set<String> = []
    let markdownFind = MarkdownFindState()
    var pdfPage = 0
    var zoom = 1.0
    var sourceQuery = ""
    var findRequest = 0
    var matchCase = false
    var loadTask: Task<Void, Never>?
    var draft: String?
    var savedText: String?
    var diskSnapshot: TextFileSnapshot?
    var previewError: String?
    var previewPending = false
    var externalChange = false
    var isSaving = false
    var isRenaming = false
    var isLoading = false
    var editRevision = 0
    var previewTask: Task<Void, Never>?
    var closeTask: Task<Void, Never>?
    @ObservationIgnored var editor: SourceEditor?
    private let previewService = FileService()

    var isDirty: Bool { draft != nil && draft != savedText }
    var canEdit: Bool { kind.hasSource && draft != nil }
    var codeLanguage: CodeLanguage? { kind == .text || kind == .json ? CodeLanguage(url: url) : nil }
    var hasPreview: Bool { kind.hasSource && (kind != .text || codeLanguage != nil) }
    var formatLabel: String { codeLanguage?.title ?? kind.label.uppercased() }
    var canUndo: Bool { _ = editRevision; return editor?.textView.undoManager?.canUndo ?? false }
    var canRedo: Bool { _ = editRevision; return editor?.textView.undoManager?.canRedo ?? false }

    func sourceEditor() -> SourceEditor {
        if let editor { return editor }
        let editor = SourceEditor(tab: self)
        self.editor = editor
        return editor
    }

    func edit(_ text: String) {
        guard draft != text else { return }
        draft = text
        editRevision += 1
        updatePreview()
    }

    func updatePreview() {
        previewTask?.cancel()
        guard let text = draft else { return }
        previewError = nil
        previewPending = false
        if kind == .markdown { state = .ready(.markdown(text)); return }
        if kind == .text { state = .ready(.text(text)); return }
        previewPending = true
        let revision = editRevision
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let payload = await previewService.parse(text, kind: kind, delimiter: url.pathExtension.lowercased() == "tsv" ? "\t" : ",")
                guard !Task.isCancelled, revision == editRevision else { return }
                applyPreview(payload)
            } catch { }
        }
    }

    func applyPreview(_ payload: FilePayload) {
        previewError = nil
        previewPending = false
        switch payload {
        case .text(let text): state = .ready(.text(text))
        case .markdown(let text): state = .ready(.markdown(text))
        case .json(let text, let root): state = .ready(.json(text, root))
        case .table(let text, let table): state = .ready(.table(text, table))
        case .invalidStructured(let text, let error): state = .ready(.text(text)); previewError = error
        case .native: state = .ready(.native)
        }
    }

    func acceptDisk(_ snapshot: TextFileSnapshot) {
        previewTask?.cancel()
        diskSnapshot = snapshot
        draft = snapshot.text; savedText = snapshot.text
        externalChange = false
        editRevision += 1
        editor?.replaceFromDisk(snapshot.text)
    }

    func discardEdits() {
        guard let savedText else { return }
        draft = savedText
        editRevision += 1
        editor?.replaceFromDisk(savedText)
        updatePreview()
    }

    init(url: URL, readingSession: MarkdownReadingSession? = nil) {
        self.url = url
        kind = DocumentKind(url: url)
        self.readingSession = readingSession
        markdownLocation = readingSession?.location
        markdownOffset = readingSession?.location?.offset ?? 0
    }

    func relocate(to url: URL, readingSession: MarkdownReadingSession?) {
        let previousKind = kind
        self.url = url
        let renamedKind = DocumentKind(url: url)
        // A suffix change must not hide an existing editable draft (e.g. note.txt -> note.bin).
        kind = draft != nil && !renamedKind.hasSource ? .text : renamedKind
        self.readingSession = readingSession
        if draft != nil {
            if kind != previousKind { showSource = true }
            updatePreview()
        }
    }

    func rememberReadingPosition(_ location: MarkdownReadingLocation) {
        markdownLocation = location
        markdownOffset = location.offset
        readingSession?.remember(location)
    }
}

/// Serializes file I/O away from the UI. The workspace caches directory results.
actor FileService {
    func children(of url: URL) throws -> [FileEntry] { try FileReader.children(of: url) }

    func read(_ url: URL, kind: DocumentKind) throws -> ReadFileResult {
        if !kind.hasSource { return ReadFileResult(payload: .native, snapshot: nil) }
        let snapshot = try TextFileStore.read(at: url)
        return ReadFileResult(payload: parse(snapshot.text, kind: kind, delimiter: url.pathExtension.lowercased() == "tsv" ? "\t" : ","), snapshot: snapshot)
    }

    func parse(_ text: String, kind: DocumentKind, delimiter: Character = ",") -> FilePayload {
        switch kind {
        case .markdown: return .markdown(text)
        case .json:
            do { return .json(text, try JSONNode.parse(text)) }
            catch { return .invalidStructured(text, error.localizedDescription) }
        case .table:
            do { return .table(text, try CSVDocument(text, delimiter: delimiter)) }
            catch { return .invalidStructured(text, error.localizedDescription) }
        default: return .text(text)
        }
    }

    func save(_ text: String, at url: URL, format: TextFileSnapshot, expected: DiskVersion) throws -> TextFileSnapshot {
        try TextFileStore.save(text, at: url, format: format, expected: expected)
    }

    func version(at url: URL) throws -> DiskVersion { try TextFileStore.version(at: url) }

    func createEmptyFile(named name: String, in folder: URL) throws -> URL {
        try FileCreator.createEmptyFile(named: name, in: folder)
    }

    func moveItem(at url: URL, into folder: URL) throws -> URL {
        try FileMover.move(url, into: folder)
    }

    func renameItem(at url: URL, to name: String) throws -> URL {
        try FileRenamer.rename(url, to: name)
    }

    func createDirectory(named name: String, in folder: URL) throws -> URL {
        try FileCreator.createDirectory(named: name, in: folder)
    }

    func moveToTrash(at url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }

    func search(_ query: String, roots: [URL]) throws -> [FileEntry] {
        var results: [FileEntry] = []
        var scanned = 0
        for root in roots {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                try Task.checkCancellation()
                scanned += 1
                if scanned > 25_000 || results.count >= 200 { return results }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true {
                    if ["node_modules", "target", "build", "dist", "vendor"].contains(url.lastPathComponent) {
                        enumerator?.skipDescendants()
                    }
                } else if url.lastPathComponent.localizedCaseInsensitiveContains(query) {
                    results.append(FileEntry(url: url, isDirectory: false))
                }
            }
        }
        return results
    }
}

enum FilePayload: Sendable {
    case text(String), markdown(String), json(String, JSONNode), table(String, CSVDocument)
    case invalidStructured(String, String), native
}

struct ReadFileResult: Sendable {
    let payload: FilePayload
    let snapshot: TextFileSnapshot?
}

@Observable final class Workspace {
    var roots: [URL] = []
    var directories: [URL: [FileEntry]] = [:]
    var directoryErrors: [URL: String] = [:]
    var loadingDirectories: Set<URL> = []
    var expanded: Set<URL> = []
    var tabs: [DocumentTab] = [] { didSet { persistSession() } }
    var activeID: URL? { didSet { persistSession() } }
    var query = ""
    var searchResults: [FileEntry] = []
    var searching = false
    var searchError: String?
    var recent: [URL] = []
    var notice: String?
    var newItemRequest: NewItemRequest?
    var trashRequest: FileEntry?
    var renameRequest: FileEntry?
    private(set) var isRenaming = false
    let dragWorkspaceID = UUID()
    @ObservationIgnored var draggedItem: SidebarDragItem?
    var isMutatingFiles: Bool { isTrashing || isRenaming }
    private(set) var isTrashing = false
    var appearance: AppAppearance {
        didSet { preferences.set(appearance.rawValue, forKey: "appearance") }
    }
    var editorFontSize: Double {
        didSet {
            preferences.set(editorFontSize, forKey: "editorFontSize")
            for tab in tabs { tab.editor?.setFontSize(editorFontSize) }
        }
    }
    var previewFullWidth: Bool { didSet { preferences.set(previewFullWidth, forKey: "previewFullWidth") } }
    var previewMaxWidth: Double { didSet { preferences.set(previewMaxWidth, forKey: "previewMaxWidth") } }
    var markdownPreviewWidth: Double { previewFullWidth ? 0 : min(1_600, max(640, previewMaxWidth)) }
    var markdownFont: MarkdownFont { didSet { preferences.set(markdownFont.rawValue, forKey: "markdownFont") } }
    var markdownFontSize: Double { didSet { preferences.set(markdownFontSize, forKey: "markdownFontSize") } }
    var markdownLineHeight: Double { didSet { preferences.set(markdownLineHeight, forKey: "markdownLineHeight") } }
    var markdownTypography: MarkdownTypography {
        .init(font: markdownFont, fontSize: markdownFontSize, lineHeight: markdownLineHeight)
    }
    var showFind = false
    var findFocusRequest = 0
    let files: FileService
    let readingHistory: MarkdownReadingHistory
    private let preferences: UserDefaults
    private var searchTask: Task<Void, Never>?
    private var pendingDirectoryRefreshes: Set<URL> = []
    private var directoryGeneration = 0
    @ObservationIgnored private var lastAutomaticDirectoryRefresh: ContinuousClock.Instant?
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?
    private var restoring = false
    private var didRestore = false
    private var pendingCaptures: [UUID: Task<Void, Never>] = [:]
    private var closingTabs: Set<URL> = []
    private var reviewingUnsaved = false
    private var askingUnsaved = false
    private var pendingWindowDiscards: [(tab: DocumentTab, revision: Int)] = []
    @ObservationIgnored var chooseUnsaved: (DocumentTab) async -> UnsavedChoice = DocumentDialogs.unsaved
    @ObservationIgnored var chooseConflict: (DocumentTab) async -> ConflictChoice = DocumentDialogs.conflict
    @ObservationIgnored var recycleItem: @MainActor (URL) async throws -> Void
    @ObservationIgnored var renameItem: @MainActor (URL, String) async throws -> URL
    @ObservationIgnored var moveItem: @MainActor (URL, URL) async throws -> URL

    var activeTab: DocumentTab? { tabs.first { $0.id == activeID } }
    var samplesURL: URL? { Bundle.module.url(forResource: "Samples", withExtension: nil) }

    var canFind: Bool { activeTab.map { $0.kind.hasSource || $0.kind == .pdf } ?? false }
    var canFindNext: Bool {
        guard let tab = activeTab else { return false }
        return tab.kind == .markdown && !tab.showSource ? tab.markdownFind.canMove : !tab.sourceQuery.isEmpty
    }
    var canFindPrevious: Bool { activeTab.map { $0.kind == .markdown && !$0.showSource && $0.markdownFind.canMove } ?? false }

    func openFind() {
        guard canFind else { return }
        showFind = true
        findFocusRequest += 1
    }

    func advanceFind(_ direction: Int) {
        guard let tab = activeTab else { return }
        if tab.kind == .markdown && !tab.showSource { tab.markdownFind.move(direction) }
        else if direction > 0 && !tab.sourceQuery.isEmpty { tab.findRequest += 1 }
    }

    func imageRoot(for document: URL) -> URL {
        roots.filter { document.path.hasPrefix($0.path + "/") || $0.path == "/" }
            .max { $0.path.count < $1.path.count } ?? document.deletingLastPathComponent()
    }

    init(preferences: UserDefaults = .standard) {
        let service = FileService()
        files = service
        recycleItem = { url in _ = try await service.moveToTrash(at: url) }
        renameItem = { url, name in try await service.renameItem(at: url, to: name) }
        moveItem = { url, folder in try await service.moveItem(at: url, into: folder) }
        self.preferences = preferences
        readingHistory = MarkdownReadingHistory(preferences: preferences)
        appearance = AppAppearance(rawValue: preferences.string(forKey: "appearance") ?? "") ?? .system
        editorFontSize = EditorTypography.validFontSize(preferences.double(forKey: "editorFontSize"))
        previewFullWidth = preferences.object(forKey: "previewFullWidth") as? Bool ?? true
        let savedWidth = preferences.double(forKey: "previewMaxWidth")
        previewMaxWidth = savedWidth.isFinite && (640...1_600).contains(savedWidth) ? savedWidth : 1_100
        let typography = MarkdownTypography(
            font: MarkdownFont(rawValue: preferences.string(forKey: "markdownFont") ?? "") ?? .system,
            fontSize: preferences.double(forKey: "markdownFontSize"),
            lineHeight: preferences.double(forKey: "markdownLineHeight")
        )
        markdownFont = typography.font
        markdownFontSize = typography.fontSize
        markdownLineHeight = typography.lineHeight
        recent = (preferences.stringArray(forKey: "recentFolders") ?? []).map { URL(fileURLWithPath: $0) }
    }

    func restore() {
        guard !didRestore else { return }
        didRestore = true
        restoring = true
        for path in preferences.stringArray(forKey: "workspaceFolders") ?? [] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) { addFolder(url) }
        }
        let paths = preferences.stringArray(forKey: "openFileTabs") ?? []
        let selected = preferences.string(forKey: "activeFileTab")
        open(paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) })
        if let selected, let tab = tabs.first(where: { $0.url.path == selected }) { activeID = tab.id }
        restoring = false
        // addFolder has already scheduled fresh directory reads for this launch.
        if !roots.isEmpty { lastAutomaticDirectoryRefresh = .now }
        persistSession()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "打开文件"
        panel.prompt = "打开"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { open(panel.urls) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "添加文件夹"
        panel.prompt = "添加到工作区"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { addFolder(url) }
    }

    func addFolder(_ url: URL) {
        let normalized = url.resolvingSymlinksInPath().standardizedFileURL
        guard !roots.contains(normalized) else { return }
        roots.append(normalized)
        expanded.insert(normalized)
        loadDirectory(normalized)
        if !restoring {
            recent.removeAll { $0 == normalized }
            recent.insert(normalized, at: 0)
            recent = Array(recent.prefix(8))
            persistRoots()
        }
    }

    func removeFolder(_ url: URL) {
        let normalized = url.resolvingSymlinksInPath().standardizedFileURL
        roots.removeAll { $0 == normalized }
        expanded.remove(normalized)
        persistRoots()
    }

    private func persistRoots() {
        preferences.set(roots.map(\.path), forKey: "workspaceFolders")
        preferences.set(recent.map(\.path), forKey: "recentFolders")
    }

    private func persistSession() {
        guard !restoring else { return }
        preferences.set(tabs.map { $0.url.path }, forKey: "openFileTabs")
        preferences.set(activeID?.path, forKey: "activeFileTab")
    }

    func prepareForTermination() async {
        for tab in tabs { await tab.captureMarkdownPosition?() }
        for task in Array(pendingCaptures.values) { await task.value }
        readingHistory.flush()
        persistSession()
    }

    func addReadingBookmark() {
        guard let tab = activeTab, tab.kind == .markdown, !tab.showSource else { return }
        tab.markdownBookmarkRequest += 1
    }

    @discardableResult func createFile(named name: String, in folder: URL) async throws -> URL {
        guard !isMutatingFiles else { throw WorkspaceRenameError.busy }
        let file = try await files.createEmptyFile(named: name, in: folder)
        // Use the tree row's exact URL as its cache/expansion key.
        let directory = folder
        expanded.insert(directory)
        loadDirectory(directory, refresh: true)
        if !query.isEmpty { search() }
        open([file])
        if let tab = activeTab, tab.kind.hasSource { tab.showSource = true }
        return file
    }

    @discardableResult func createFolder(named name: String, in folder: URL) async throws -> URL {
        guard !isMutatingFiles else { throw WorkspaceRenameError.busy }
        let created = try await files.createDirectory(named: name, in: folder)
        expanded.insert(folder)
        loadDirectory(folder, refresh: true)
        if !query.isEmpty { search() }
        return created
    }

    /// Event-driven refresh only: startup/activation share a monotonic 30-second cooldown.
    @discardableResult func refreshDirectoriesAutomatically(at now: ContinuousClock.Instant = .now) -> Bool {
        guard !roots.isEmpty else { return false }
        if let last = lastAutomaticDirectoryRefresh, last.duration(to: now) < .seconds(30) { return false }
        lastAutomaticDirectoryRefresh = now
        refreshDirectories()
        return true
    }

    func refreshDirectories() {
        let scope = roots.map(WorkspacePath.normalized)
        for directory in Set(roots).union(directories.keys).union(expanded) {
            let path = WorkspacePath.normalized(directory)
            guard scope.contains(where: { WorkspacePath.contains($0, path) }) else { continue }
            loadDirectory(directory, refresh: true)
        }
        if !query.isEmpty { search() }
    }

    func loadDirectory(_ url: URL, refresh: Bool = false) {
        if loadingDirectories.contains(url) {
            if refresh { pendingDirectoryRefreshes.insert(url) }
            return
        }
        guard refresh || directories[url] == nil else { return }
        loadingDirectories.insert(url)
        let generation = directoryGeneration
        Task {
            defer {
                if generation == directoryGeneration {
                    loadingDirectories.remove(url)
                    if pendingDirectoryRefreshes.remove(url) != nil { loadDirectory(url, refresh: true) }
                }
            }
            do {
                let entries = try await files.children(of: url)
                guard generation == directoryGeneration else { return }
                directories[url] = entries
                directoryErrors[url] = nil
            } catch { if generation == directoryGeneration { directoryErrors[url] = error.localizedDescription } }
        }
    }

    func toggleDirectory(_ url: URL) {
        if expanded.contains(url) { expanded.remove(url) }
        else { expanded.insert(url); loadDirectory(url) }
    }

    func open(_ urls: [URL]) {
        guard !isRenaming else { notice = "正在更新文件路径，请完成后再打开文件。"; return }
        for url in urls {
            let url = url.resolvingSymlinksInPath().standardizedFileURL
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                addFolder(url)
                continue
            }
            if let tab = tabs.first(where: { $0.id == url }) { activeID = tab.id; continue }
            let tab = DocumentTab(url: url, readingSession: DocumentKind(url: url) == .markdown ? readingHistory.session(for: url) : nil)
            tabs.append(tab)
            activeID = tab.id
            load(tab)
        }
    }

    func load(_ tab: DocumentTab) {
        guard !tab.isDirty, !tab.isSaving, !tab.isLoading, !tab.isRenaming else {
            notice = "\(tab.title) 有未保存的修改，请先保存或使用重新载入。"
            return
        }
        readFromDisk(tab)
    }

    private func readFromDisk(_ tab: DocumentTab) {
        let previous = tab.state
        tab.loadTask?.cancel()
        tab.previewTask?.cancel()
        tab.isLoading = true
        tab.state = .loading
        tab.loadTask = Task {
            do {
                let result = try await files.read(tab.url, kind: tab.kind)
                guard !Task.isCancelled else { return }
                if let snapshot = result.snapshot { tab.acceptDisk(snapshot) }
                tab.applyPreview(result.payload)
                if case .invalidStructured(_, let message) = result.payload {
                    tab.showSource = true
                    notice = "\(tab.title)：\(message) 已打开源码。"
                }
                tab.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                tab.isLoading = false
                if tab.draft != nil {
                    tab.state = previous
                    tab.updatePreview()
                    notice = "无法重新载入 \(tab.title)：\(error.localizedDescription) 编辑内容仍保留。"
                } else { tab.state = .ready(.failed(error.localizedDescription)) }
            }
        }
    }

    func close(_ id: URL) {
        guard let tab = tabs.first(where: { $0.id == id }), !tab.isSaving, !tab.isRenaming else { return }
        if !tab.isDirty { removeTab(id); return }
        guard closingTabs.insert(id).inserted else { return }
        tab.closeTask = Task {
            defer { closingTabs.remove(id); tab.closeTask = nil }
            guard await resolveUnsaved(tab) != .cancel else { return }
            removeTab(id)
        }
    }

    private func removeTab(_ id: URL) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        let capture = UUID()
        pendingCaptures[capture] = Task {
            defer { pendingCaptures[capture] = nil }
            await tab.captureMarkdownPosition?()
            readingHistory.flush()
        }
        tabs[index].loadTask?.cancel()
        tab.previewTask?.cancel()
        tab.editor?.textView.undoManager?.removeAllActions()
        tabs.remove(at: index)
        if activeID == id { activeID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id }
    }

    @discardableResult func rename(_ entry: FileEntry, to input: String) async throws -> URL {
        guard !isMutatingFiles, !reviewingUnsaved, !askingUnsaved else { throw WorkspaceRenameError.busy }
        let name = try FileCreator.validatedName(input)
        let destination = entry.url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(name, isDirectory: entry.isDirectory)
        return try await relocate(entry, to: destination) { try await renameItem(entry.url, name) }
    }

    @discardableResult func move(_ entry: FileEntry, into folder: URL) async throws -> URL {
        guard !isMutatingFiles else { throw WorkspaceRenameError.busy }
        let scope = roots.map(WorkspacePath.normalized)
        guard scope.contains(where: { WorkspacePath.contains($0, WorkspacePath.item(entry.url)) }),
              scope.contains(where: { WorkspacePath.contains($0, WorkspacePath.normalized(folder)) }) else { throw WorkspaceMoveError.outsideWorkspace }
        let destination = try FileMover.destination(for: entry.url, in: folder)
        let actual = FileEntry(url: entry.url, isDirectory: destination.hasDirectoryPath)
        let moved = try await relocate(actual, to: destination) { try await moveItem(entry.url, folder) }
        expanded.insert(folder)
        loadDirectory(folder, refresh: true)
        return moved
    }

    private func relocate(_ entry: FileEntry, to destination: URL, operation: () async throws -> URL) async throws -> URL {
        guard !isMutatingFiles, !reviewingUnsaved, !askingUnsaved else { throw WorkspaceRenameError.busy }
        let oldPath = WorkspacePath.item(entry.url)
        func mapped(_ url: URL) -> URL? {
            let path = WorkspacePath.item(url)
            if path == oldPath { return destination }
            guard entry.isDirectory, WorkspacePath.contains(oldPath, path) else { return nil }
            return destination.appendingPathComponent(String(path.dropFirst(oldPath.count + 1)), isDirectory: url.hasDirectoryPath)
        }
        let affected = tabs.compactMap { tab -> (DocumentTab, URL, String)? in
            guard let url = mapped(tab.url) else { return nil }
            return (tab, url, MarkdownReadingHistory.storageKey(for: tab.url))
        }
        guard affected.allSatisfy({ !$0.0.isSaving && !$0.0.isLoading && $0.0.closeTask == nil }) else { throw WorkspaceRenameError.busy }
        for (tab, url, _) in affected {
            if tabs.contains(where: { $0 !== tab && WorkspacePath.item($0.url) == WorkspacePath.item(url) }) { throw WorkspaceRenameError.targetOpen }
        }
        isRenaming = true
        for (tab, _, _) in affected { tab.isRenaming = true }
        defer {
            isRenaming = false
            for (tab, _, _) in affected { tab.isRenaming = false }
        }
        for (tab, _, _) in affected { await tab.captureMarkdownPosition?() }
        for task in Array(pendingCaptures.values) { await task.value }
        let renamed = try await operation()
        let selected = activeID
        for (tab, url, key) in affected {
            readingHistory.relocate(fromKey: key, to: url)
            let session = DocumentKind(url: url) == .markdown || tab.readingSession != nil ? readingHistory.session(for: url) : nil
            tab.relocate(to: url, readingSession: session)
            if tab.draft == nil { readFromDisk(tab) }
        }
        func relocatedUnique(_ urls: [URL]) -> [URL] {
            var seen: Set<String> = []
            return urls.map { mapped($0) ?? $0 }.filter { seen.insert(WorkspacePath.item($0)).inserted }
        }
        roots = relocatedUnique(roots)
        recent = relocatedUnique(recent)
        expanded = Set(expanded.map { mapped($0) ?? $0 })
        directoryGeneration += 1
        loadingDirectories.removeAll()
        pendingDirectoryRefreshes.removeAll()
        var relocatedDirectories: [URL: [FileEntry]] = [:]
        for (url, entries) in directories.sorted(by: { (mapped($0.key) == nil ? 0 : 1) < (mapped($1.key) == nil ? 0 : 1) }) {
            relocatedDirectories[mapped(url) ?? url] = entries.map { FileEntry(url: mapped($0.url) ?? $0.url, isDirectory: $0.isDirectory) }
        }
        directories = relocatedDirectories
        directoryErrors.removeAll()
        if let selected { activeID = mapped(selected) ?? selected }
        persistRoots()
        persistSession()
        let scope = roots.map(WorkspacePath.normalized)
        for parent in [entry.url.deletingLastPathComponent(), destination.deletingLastPathComponent()] {
            if scope.contains(where: { WorkspacePath.contains($0, WorkspacePath.normalized(parent)) }) { loadDirectory(parent, refresh: true) }
        }
        refreshDirectories()
        return renamed
    }

    @discardableResult func trash(_ entry: FileEntry) async -> Bool {
        guard !isMutatingFiles, !reviewingUnsaved else { return false }
        isTrashing = true
        reviewingUnsaved = true
        defer { isTrashing = false; reviewingUnsaved = false }
        let path = WorkspacePath.item(entry.url)
        func affectedTabs() -> [DocumentTab] {
            tabs.filter {
                let candidate = WorkspacePath.item($0.url)
                return candidate == path || (entry.isDirectory && WorkspacePath.contains(path, candidate))
            }
        }
        let affected = affectedTabs()
        var reviewed: [(tab: DocumentTab, revision: Int, discard: Bool)] = []
        for tab in affected {
            guard !tab.isLoading, !tab.isSaving else {
                notice = "文档正在读写，请稍后再移到废纸篓。"
                return false
            }
            switch await resolveUnsaved(tab) {
            case .cancel: return false
            case .discard: reviewed.append((tab, tab.editRevision, true))
            case .save: reviewed.append((tab, tab.editRevision, false))
            }
        }
        guard affectedTabs().map(\.id) == affected.map(\.id), reviewed.allSatisfy({
            !$0.tab.isSaving && !$0.tab.isLoading && (!$0.tab.isDirty || ($0.discard && $0.tab.editRevision == $0.revision))
        }) else {
            notice = "文档在确认期间又有变化，已取消移到废纸篓。"
            return false
        }
        do { try await recycleItem(entry.url) }
        catch {
            notice = "无法将“\(entry.name)”移到废纸篓：\(error.localizedDescription)"
            return false
        }
        var keptNewEdits = false
        for tab in affectedTabs() {
            if let item = reviewed.first(where: { $0.tab === tab }),
               !tab.isSaving, !tab.isLoading,
               !tab.isDirty || (item.discard && tab.editRevision == item.revision) {
                removeTab(tab.id)
            } else {
                tab.externalChange = true
                keptNewEdits = true
            }
        }
        if entry.isDirectory {
            let removed = { (url: URL) in WorkspacePath.contains(path, WorkspacePath.item(url)) }
            roots.removeAll(where: removed)
            recent.removeAll(where: removed)
            expanded = Set(expanded.filter { !removed($0) })
            for url in Array(directories.keys) where removed(url) { directories[url] = nil; directoryErrors[url] = nil }
            persistRoots()
        }
        refreshDirectories()
        notice = keptNewEdits ? "已移到废纸篓；操作期间产生的新编辑仍保留在标签页中。" : nil
        return true
    }

    func moveTab(_ offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == activeID }), !tabs.isEmpty else { return }
        activeID = tabs[(index + offset + tabs.count) % tabs.count].id
    }

    func refresh() {
        // Manual refresh always updates the tree, even while a document refresh is in progress.
        refreshDirectories()
        guard refreshTask == nil, let tab = activeTab else { return }
        refreshTask = Task {
            defer { refreshTask = nil }
            guard tabs.contains(where: { $0 === tab }) else { return }
            _ = await reload(tab)
        }
    }

    func saveActive() { if let tab = activeTab { Task { await save(tab) } } }

    func undo() { activeTab?.editor?.textView.breakUndoCoalescing(); activeTab?.editor?.textView.undoManager?.undo() }
    func redo() { activeTab?.editor?.textView.breakUndoCoalescing(); activeTab?.editor?.textView.undoManager?.redo() }

    @discardableResult func save(_ tab: DocumentTab) async -> Bool {
        guard let text = tab.draft, let snapshot = tab.diskSnapshot, !tab.isSaving, !tab.isLoading, !tab.isRenaming else { return false }
        if !tab.isDirty && !tab.externalChange { return true }
        tab.editor?.textView.breakUndoCoalescing()
        tab.isSaving = true
        defer { tab.isSaving = false }
        var expected = snapshot.version
        while true {
            do {
                let saved = try await files.save(text, at: tab.url, format: snapshot, expected: expected)
                tab.diskSnapshot = saved
                tab.savedText = text
                tab.externalChange = false
                notice = nil
                return true
            } catch TextFileWriteError.changed(let current) {
                tab.externalChange = true
                switch await chooseConflict(tab) {
                case .cancel: return false
                case .reload:
                    readFromDisk(tab)
                    await tab.loadTask?.value
                    return false
                case .overwrite: expected = current
                }
            } catch {
                notice = "无法保存 \(tab.title)：\(error.localizedDescription) 编辑内容仍保留。"
                return false
            }
        }
    }

    func resolveUnsaved(_ tab: DocumentTab) async -> UnsavedChoice {
        guard !tab.isSaving, !tab.isRenaming else { return .cancel }
        guard tab.isDirty else { return .discard }
        guard !askingUnsaved else { return .cancel }
        askingUnsaved = true
        defer { askingUnsaved = false }
        switch await chooseUnsaved(tab) {
        case .save: return await save(tab) && !tab.isDirty ? .save : .cancel
        case .discard: return .discard
        case .cancel: return .cancel
        }
    }

    @discardableResult func reload(_ tab: DocumentTab) async -> Bool {
        guard !tab.isLoading, !tab.isRenaming, await resolveUnsaved(tab) != .cancel else { return false }
        readFromDisk(tab)
        await tab.loadTask?.value
        return !tab.isDirty
    }

    func confirmCloseAll(commitDiscards: Bool = true) async -> Bool {
        guard !reviewingUnsaved, !isRenaming else { return false }
        reviewingUnsaved = true
        defer { reviewingUnsaved = false }
        let ids = tabs.map(\.id)
        var reviewed: [(tab: DocumentTab, revision: Int, discard: Bool)] = []
        for tab in tabs {
            switch await resolveUnsaved(tab) {
            case .cancel: return false
            case .discard: reviewed.append((tab, tab.editRevision, true))
            case .save: reviewed.append((tab, tab.editRevision, false))
            }
        }
        await prepareForTermination()
        guard tabs.map(\.id) == ids, reviewed.allSatisfy({ item in
            !item.tab.isSaving && !item.tab.isLoading && (!item.tab.isDirty || (item.discard && item.tab.editRevision == item.revision))
        }) else {
            notice = "检查保存期间文档又有变化，已取消关闭，请检查最新修改。"
            return false
        }
        let discarded = reviewed.filter { $0.discard && $0.tab.isDirty }.map { (tab: $0.tab, revision: $0.revision) }
        if commitDiscards {
            for item in discarded { item.tab.discardEdits() }
        } else { pendingWindowDiscards = discarded }
        return true
    }

    func commitWindowDiscards() -> Bool {
        let discarded = pendingWindowDiscards
        pendingWindowDiscards = []
        guard discarded.allSatisfy({ $0.tab.editRevision == $0.revision }) else { return false }
        for item in discarded { item.tab.discardEdits() }
        return true
    }

    func checkExternalChanges() async {
        for tab in tabs {
            guard let snapshot = tab.diskSnapshot, !tab.isSaving, !tab.isLoading, !tab.isRenaming else { continue }
            let url = tab.url
            do {
                let version = try await files.version(at: url)
                guard tab.url == url, !tab.isSaving, !tab.isLoading, !tab.isRenaming, tab.diskSnapshot?.version == snapshot.version else { continue }
                tab.externalChange = version != snapshot.version
            } catch {
                if tab.url == url, !tab.isSaving, !tab.isLoading, !tab.isRenaming, tab.diskSnapshot?.version == snapshot.version { tab.externalChange = true }
            }
        }
    }

    func search() {
        searchTask?.cancel()
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchResults = []
        searchError = nil
        guard !value.isEmpty else { searching = false; return }
        searching = true
        let scope = roots
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                let results = try await files.search(value, roots: scope)
                guard !Task.isCancelled else { return }
                searchResults = results
                searching = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { searchError = error.localizedDescription; searching = false } }
        }
    }

    func openSamples() {
        guard let folder = samplesURL else { return }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let parent = support.appendingPathComponent("Luma", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let editable = parent.appendingPathComponent("Samples-0.8", isDirectory: true)
            if !FileManager.default.fileExists(atPath: editable.path) { try FileManager.default.copyItem(at: folder, to: editable) }
            addFolder(editable)
            open([editable.appendingPathComponent("欢迎.md")])
        } catch { notice = "无法创建可编辑的示例工作区：\(error.localizedDescription)" }
    }
}
