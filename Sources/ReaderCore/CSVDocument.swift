import Foundation

public struct CSVDocument: Sendable {
    public let rows: [[String]]
    public let columnCount: Int

    /// Handles quoted delimiters, escaped quotes, CRLF and multiline fields.
    public init(_ text: String, delimiter: Character = ",") throws {
        enum State { case field, quoted, afterQuote }
        var state = State.field
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var endedRow = false
        var previousCR = false

        func appendField() throws {
            guard row.count < 200 else { throw ReaderError.tooManyColumns }
            row.append(field)
            field = ""
        }
        func appendRow() throws {
            try appendField()
            guard rows.count < 10_000 else { throw ReaderError.tooManyRows }
            rows.append(row)
            row = []
        }

        for character in text {
            if previousCR && character == "\n" { previousCR = false; continue }
            previousCR = false
            endedRow = false
            if state == .quoted {
                if character == "\"" { state = .afterQuote }
                else { field.append(character) }
                continue
            }
            if state == .afterQuote && character == "\"" {
                field.append("\"")
                state = .quoted
            } else if character == delimiter {
                try appendField()
                state = .field
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                try appendRow()
                state = .field
                endedRow = true
                previousCR = character == "\r"
            } else if state == .afterQuote {
                throw ReaderError.invalidCSV("引号结束后存在多余字符")
            } else if character == "\"" {
                guard field.isEmpty else { throw ReaderError.invalidCSV("字段中存在未转义的引号") }
                state = .quoted
            } else {
                field.append(character)
            }
        }
        guard state != .quoted else { throw ReaderError.invalidCSV("引号未闭合") }
        if !endedRow && (!text.isEmpty || !row.isEmpty || !field.isEmpty) { try appendRow() }
        self.rows = rows
        columnCount = rows.map(\.count).max() ?? 0
    }
}
