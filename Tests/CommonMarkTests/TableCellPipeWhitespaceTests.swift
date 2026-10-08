/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Under Tables (extension), spaces between pipes and cell content are trimmed. Directly after a pipe, the parser
/// also skips tabs, line tabulations (U+000B) and form feeds (U+000C), which are whitespace characters, so a trailing
/// pipe followed only by them closes its row. Elsewhere, only spaces and tabs are trimmed from a cell's edges, and a
/// line tabulation or form feed is cell content.
@Suite("Table cell pipe-boundary whitespace")
struct TableCellPipeWhitespaceTests {

    private static let ff = "\u{0C}"  // form feed
    private static let vt = "\u{0B}"  // line tabulation

    /// Every row's cell texts, `[header, body1, ...]`, for the first `.table` in the tree; `nil` if none.
    private func tableRows(_ source: String) -> [[String]]? {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> [[String]]? in
            func firstTable(_ node: borrowing MarkdownNode) -> [[String]]? {
                if case .table = node.kind {
                    var rows: [[String]] = []
                    node.children.forEach { row in
                        guard case .tableRow = row.kind else { return }
                        var cells: [String] = []
                        row.children.forEach { cell in
                            guard case .tableCell = cell.kind else { return }
                            var text = ""
                            cell.children.forEach { if let lit = $0.literal() { text += lit } }
                            cells.append(text)
                        }
                        rows.append(cells)
                    }
                    return rows
                }
                var found: [[String]]? = nil
                node.children.forEach { if found == nil { found = firstTable($0) } }
                return found
            }
            return firstTable(doc.root)
        }
    }

    /// The first top-level block's kind: "paragraph" / "heading" / "table" / "other".
    private func firstBlockKind(_ source: String) -> String {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> String in
            var kinds: [String] = []
            doc.root.children.forEach { child in
                switch child.kind {
                case .paragraph: kinds.append("paragraph")
                case .heading: kinds.append("heading")
                case .table: kinds.append("table")
                default: kinds.append("other")
                }
            }
            return kinds.first ?? "none"
        }
    }

    // MARK: - Whitespace after a pipe

    @Test("a form feed after an interior header pipe is not part of the next cell")
    func interiorHeaderFormFeed() throws {
        let rows = try #require(tableRows("a|\(Self.ff)b\n-|-"))
        #expect(rows.first == ["a", "b"])
    }

    @Test("a form feed after an interior body pipe is not part of the next cell")
    func interiorBodyFormFeed() throws {
        let rows = try #require(tableRows("a|b\n-|-\nc|\(Self.ff)d"))
        #expect(rows == [["a", "b"], ["c", "d"]])
    }

    @Test("a trailing pipe then a form feed is a closing pipe on the delimiter row")
    func delimiterTrailingPipeFormFeed() throws {
        let rows = try #require(tableRows("d\n-|\(Self.ff)"))
        #expect(rows == [["d"]])
    }

    @Test("a trailing pipe then a line tabulation is a closing pipe on the delimiter row")
    func delimiterTrailingPipeVerticalTab() throws {
        let rows = try #require(tableRows("d\n-|\(Self.vt)"))
        #expect(rows == [["d"]])
    }

    @Test("a trailing pipe then a form feed closes the header row, so a three-cell delimiter row forms no table")
    func trailingHeaderPipeFormFeedMismatch() {
        // The header row and delimiter row must have the same number of cells.
        #expect(firstBlockKind("a|b|\(Self.ff)\n-|-|-") == "paragraph")
    }

    // MARK: - Other cell edges

    @Test("a form feed before a pipe is cell content")
    func formFeedBeforePipeIsContent() throws {
        let rows = try #require(tableRows("a\(Self.ff)|b\n-|-"))
        #expect(rows.first == ["a\(Self.ff)", "b"])
    }

    @Test("a form feed starting a first cell with no leading pipe is cell content")
    func leadingFormFeedFirstCellNoPipe() throws {
        let rows = try #require(tableRows("\(Self.ff)a|b\n-|-"))
        #expect(rows.first == ["\(Self.ff)a", "b"])
    }

    @Test("a line tabulation starting a first cell with no leading pipe is cell content")
    func leadingVerticalTabFirstCellNoPipe() throws {
        let rows = try #require(tableRows("\(Self.vt)a|b\n-|-"))
        #expect(rows.first == ["\(Self.vt)a", "b"])
    }

    @Test("a form feed after a leading pipe is skipped")
    func leadingFormFeedFirstCellWithPipe() throws {
        let rows = try #require(tableRows("|\(Self.ff)a|b\n-|-"))
        #expect(rows.first == ["a", "b"])
    }

    @Test("a trailing pipe then a form feed closes a body row")
    func trailingBodyPipeFormFeed() throws {
        let rows = try #require(tableRows("a|b\n-|-\nc|d|\(Self.ff)"))
        #expect(rows == [["a", "b"], ["c", "d"]])
    }

    @Test("a delimiter row with a trailing pipe forms a one-column table")
    func bareTrailingPipe() throws {
        let rows = try #require(tableRows("d\n-|"))
        #expect(rows == [["d"]])
    }

    @Test("an escaped pipe is not a cell separator")
    func escapedPipeNotSeparator() {
        // A one-cell header row doesn't match a two-cell delimiter row.
        #expect(firstBlockKind("a\\|b\n-|-") == "paragraph")
    }
}
