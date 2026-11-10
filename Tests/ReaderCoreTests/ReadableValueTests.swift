import Foundation
import Testing
@testable import ReaderCore

struct ReadableValueTests {
    @Test(arguments: ["#abc", "#abcd", "#3A6095", "#3A609580", "\"#3A6095\"", "'#abc'"])
    func interpretsHexColorsWithoutDroppingAlpha(_ source: String) throws {
        let color = try #require(ReadableValue.color(source))
        #expect(color.red >= 0 && color.red <= 1)
        #expect(ReadableValue.color(color.hex) == color)
    }
    @Test(arguments: ["#12", "#12345", "#ggg", "#３Ａ６０９５", "red", "<script>"])
    func rejectsNonHexColors(_ source: String) { #expect(ReadableValue.color(source) == nil) }
    @Test func explicitTimestampUnitsProduceDifferentInterpretations() throws {
        #expect(ReadableValue.date("1700000000000", unit: .milliseconds) == ReadableValue.date("1700000000", unit: .seconds))
        #expect(ReadableValue.date("1000", unit: .seconds)?.timeIntervalSince1970 == 1000)
        #expect(ReadableValue.date("1000", unit: .milliseconds)?.timeIntervalSince1970 == 1)
        #expect(ReadableValue.date("-1", unit: .seconds)?.timeIntervalSince1970 == -1)
        for invalid in ["nan", "inf", "1e100", "253402300800", "-62135596801"] {
            #expect(ReadableValue.date(invalid, unit: .seconds) == nil)
        }
    }
    @Test func distinguishesDecimalAndBinarySizesAndRejectsOverflow() {
        #expect(ReadableValue.byteCount("1 KB") == 1000)
        #expect(ReadableValue.byteCount("1 KiB") == 1024)
        #expect(ReadableValue.byteCount("1.5 MiB") == 1_572_864)
        #expect(ReadableValue.byteCount("\"2048\"") == 2048)
        for invalid in ["-1", "1 MB trailing", "1e100", "inf", "9007199254740992"] { #expect(ReadableValue.byteCount(invalid) == nil) }
    }
    @Test func decodesAndEncodesUnicodeAndEscapesAsData() throws {
        #expect(ReadableValue.decodedString(#""\u4F60\n\"hi\"\uD83D\uDE42""#) == "你\n\"hi\"🙂")
        #expect(ReadableValue.decodedString(#"a\tb"#) == "a\tb")
        #expect(ReadableValue.decodedString(#""\uD800""#) == nil)
        #expect(ReadableValue.decodedString(#""a" trailing"#) == nil)
        let value = "</script>\n\"中文🙂\"\\"
        #expect(ReadableValue.decodedString(ReadableValue.encodeString(value)) == value)
        #expect(ReadableValue.preservingQuotes("#FFFFFF", original: "\"#000000\"") == "\"#FFFFFF\"")
        #expect(ReadableValue.preservingQuotes("#FFFFFF", original: "#000000") == "#FFFFFF")
    }
    @Test(arguments: ["\n", "\r\n", "\r"])
    func tableSourceLinesCountQuotedMultilineRecords(newline: String) throws {
        let table = try CSVDocument("title,note" + newline + "a,\"first" + newline + "second\"" + newline + "b,last" + newline)
        #expect(table.sourceLines == [1, 2, 4])
        #expect(table.rows.count == table.sourceLines.count)
    }
}
