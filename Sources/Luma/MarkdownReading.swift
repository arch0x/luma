import Foundation
import CryptoKit
import Observation

struct MarkdownReadingLocation: Codable, Equatable, Sendable {
    var offset: Double
    var progress: Double
    var blockKey: String?
    var blockProgress: Double
    var headingID: String?
    var headingProgress: Double

    static let top = Self(offset: 0, progress: 0, blockKey: nil, blockProgress: 0, headingID: nil, headingProgress: 0)

    func validated() -> Self {
        func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        return Self(offset: offset.isFinite ? min(1_000_000_000, max(0, offset)) : 0,
                    progress: unit(progress), blockKey: blockKey.map { String($0.prefix(512)) }, blockProgress: unit(blockProgress),
                    headingID: headingID.map { String($0.prefix(200)) }, headingProgress: unit(headingProgress))
    }

    init(offset: Double, progress: Double, blockKey: String?, blockProgress: Double, headingID: String?, headingProgress: Double) {
        self.offset = offset; self.progress = progress; self.blockKey = blockKey; self.blockProgress = blockProgress
        self.headingID = headingID; self.headingProgress = headingProgress
    }

    init?(message: [String: Any]) {
        guard let offset = message["offset"] as? Double, offset.isFinite else { return nil }
        self.init(offset: offset, progress: message["progress"] as? Double ?? 0,
                  blockKey: message["blockKey"] as? String, blockProgress: message["blockProgress"] as? Double ?? 0,
                  headingID: message["headingID"] as? String, headingProgress: message["headingProgress"] as? Double ?? 0)
        self = validated()
    }

    var javascriptValue: [String: Any] {
        ["offset": offset, "progress": progress, "blockKey": blockKey ?? "", "blockProgress": blockProgress,
         "headingID": headingID ?? "", "headingProgress": headingProgress]
    }
}

struct MarkdownBookmark: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let location: MarkdownReadingLocation
    let createdAt: Date
}

private struct MarkdownReadingRecord: Codable {
    var version = 1
    var location: MarkdownReadingLocation?
    var bookmarks: [MarkdownBookmark] = []
}

@Observable final class MarkdownReadingSession {
    private(set) var location: MarkdownReadingLocation?
    private(set) var bookmarks: [MarkdownBookmark]
    @ObservationIgnored fileprivate var storageKey: String
    @ObservationIgnored private let changed: (String, MarkdownReadingRecord, Bool) -> Void

    fileprivate init(key: String, record: MarkdownReadingRecord, changed: @escaping (String, MarkdownReadingRecord, Bool) -> Void) {
        storageKey = key
        location = record.location?.validated()
        bookmarks = Array(record.bookmarks.prefix(500)).map {
            MarkdownBookmark(id: $0.id, title: String($0.title.prefix(160)), location: $0.location.validated(), createdAt: $0.createdAt)
        }
        self.changed = changed
    }

    func remember(_ value: MarkdownReadingLocation) {
        let value = value.validated()
        guard value != location else { return }
        location = value
        save(immediately: false)
    }

    @discardableResult func addBookmark(at value: MarkdownReadingLocation, title: String, chapterStart: Bool = false) -> UUID? {
        let value = value.validated()
        let label = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        if let existing = bookmarks.first(where: {
            guard $0.location.headingID == value.headingID, $0.location.blockKey == value.blockKey else { return false }
            if chapterStart && $0.title == label && $0.location.blockProgress == 0 && $0.location.headingProgress == 0 { return true }
            return abs($0.location.blockProgress - value.blockProgress) < 0.01 && abs($0.location.offset - value.offset) < 24
        }) { return existing.id }
        guard bookmarks.count < 500 else { return nil }
        let bookmark = MarkdownBookmark(id: UUID(), title: label.isEmpty ? "阅读位置" : label, location: value, createdAt: Date())
        bookmarks.append(bookmark)
        save(immediately: true)
        return bookmark.id
    }

    func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save(immediately: true)
    }

    private func save(immediately: Bool) {
        changed(storageKey, MarkdownReadingRecord(location: location, bookmarks: bookmarks), immediately)
    }
}

/// Per-file records avoid re-encoding every document on each scroll update.
final class MarkdownReadingHistory {
    private let preferences: UserDefaults
    private var sessions: [String: MarkdownReadingSession] = [:]
    private var pending: [String: MarkdownReadingRecord] = [:]
    private var saveTask: Task<Void, Never>?

    init(preferences: UserDefaults) { self.preferences = preferences }

    static func storageKey(for url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "markdownReading.v1." + digest
    }

    func session(for url: URL) -> MarkdownReadingSession {
        let key = Self.storageKey(for: url)
        if let session = sessions[key] { return session }
        let record = preferences.data(forKey: key).flatMap { try? JSONDecoder().decode(MarkdownReadingRecord.self, from: $0) }
        let restored: MarkdownReadingRecord
        if let record, record.version == 1 { restored = record }
        else { restored = MarkdownReadingRecord() }
        let session = MarkdownReadingSession(key: key, record: restored) { [weak self] key, record, immediate in
            guard let self else { return }
            pending[key] = record
            if immediate { flush() }
            else {
                saveTask?.cancel()
                saveTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(400)); self?.flush() }
                    catch is CancellationError { }
                    catch { }
                }
            }
        }
        sessions[key] = session
        return session
    }

    func relocate(fromKey oldKey: String, to url: URL) {
        let newKey = Self.storageKey(for: url)
        guard oldKey != newKey else { return }
        flush()
        if let data = preferences.data(forKey: oldKey) { preferences.set(data, forKey: newKey) }
        else { preferences.removeObject(forKey: newKey) }
        preferences.removeObject(forKey: oldKey)
        sessions[newKey] = nil
        if let session = sessions.removeValue(forKey: oldKey) {
            session.storageKey = newKey
            sessions[newKey] = session
        }
    }

    func flush() {
        saveTask?.cancel(); saveTask = nil
        for (key, record) in pending {
            if let data = try? JSONEncoder().encode(record) { preferences.set(data, forKey: key) }
        }
        pending.removeAll()
    }
}
