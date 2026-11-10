// Luma
// A small space for the files you work with.

import Foundation

struct ReadingList {
    let title: String
    var documents: [URL]

    var isEmpty: Bool { documents.isEmpty }

    func contains(_ url: URL) -> Bool {
        documents.contains(url)
    }
}
