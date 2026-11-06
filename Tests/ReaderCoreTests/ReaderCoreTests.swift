import Foundation
import Testing
@testable import ReaderCore

@Test func csvPreservesQuotedContentAndEmptyCells() throws {
    let csv = try CSVDocument("name,note,empty\r\nAlex,\"a,b\r\nsecond \"\"line\"\"\",\r\n")
    #expect(csv.rows == [["name", "note", "empty"], ["Alex", "a,b\r\nsecond \"line\"", ""]])
    #expect(csv.columnCount == 3)
}

@Test(arguments: ["a,\"unterminated", "a\"b,c", "\"a\"oops,b"])
func rejectsMalformedCSV(_ text: String) {
    #expect(throws: (any Error).self) { try CSVDocument(text) }
}

@Test func emptyAndUnevenTables() throws {
    #expect(try CSVDocument("").rows.isEmpty)
    #expect(try CSVDocument("\n").rows == [[""]])
    #expect(try CSVDocument("a,b\n1\n2,3,4").columnCount == 3)
    #expect(try CSVDocument("a\tb\n1\t2", delimiter: "\t").rows == [["a", "b"], ["1", "2"]])
}

@Test func limitsWideTables() {
    let row = Array(repeating: "x", count: 201).joined(separator: ",")
    #expect(throws: (any Error).self) { try CSVDocument(row) }
}

@Test func jsonKeepsTypesAndEscapesPaths() throws {
    let root = try JSONNode.parse(#"{"flag":true,"count":1,"name":"hello","none":null,"a/b":{"~x":2}}"#)
    let children = try #require(root.children)
    #expect(children.first { $0.key == "flag" }?.value == "true")
    #expect(children.first { $0.key == "count" }?.value == "1")
    #expect(children.first { $0.key == "name" }?.isString == true)
    #expect(children.first { $0.key == "none" }?.value == "null")
    #expect(children.first { $0.key == "a/b" }?.children?.first?.id == "/a~1b/~0x")
}

@Test func jsonSupportsRootScalars() throws {
    #expect(try JSONNode.parse("false").value == "false")
    #expect(try JSONNode.parse("42").value == "42")
    #expect(throws: (any Error).self) { try JSONNode.parse("{broken}") }
}

@Test func boundedReaderRejectsBinaryAndLargeFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("sample.txt")
    try Data([0x61, 0x00, 0x62]).write(to: file)
    #expect(throws: (any Error).self) { try FileReader.text(at: file) }
    try Data("hello".utf8).write(to: file)
    #expect(throws: (any Error).self) { try FileReader.text(at: file, limit: 4) }
    #expect(try FileReader.text(at: file, limit: 5) == "hello")
    try Data([0xEF, 0xBB, 0xBF, 0x61]).write(to: file)
    #expect(try FileReader.text(at: file) == "a")
}

@Test func directoryTreeDoesNotFollowSymlinkCycles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("loop"), withDestinationURL: directory)
    let children = try FileReader.children(of: directory)
    #expect(children.count == 1)
    #expect(children[0].isDirectory == false)
}
