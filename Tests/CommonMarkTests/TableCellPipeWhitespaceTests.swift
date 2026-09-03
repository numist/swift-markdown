/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// GFM table cell splitting around PIPES: cmark consumes whitespace after every pipe via
/// `scan_table_cell_end = [|] spacechar*` with `spacechar = [ \t\v\f]` (space, tab, vertical-tab
/// U+000B, form-feed U+000C). So VT/FF immediately following a pipe is NOT part of the next cell, and
/// a trailing `|` followed only by VT/FF is still a closing pipe. Cell CONTENT is otherwise trimmed by
/// `cmark_strbuf_trim` (space/tab only — VT/FF NOT adjacent to a pipe stays content).
///
/// The rewrite's `splitCells` trimmed cell edges with space/tab only, so FF/VT right after a pipe
/// leaked into the next cell's text, and a trailing `|` then VT/FF became a spurious empty cell. This
/// suite pins cmark's pipe-boundary whitespace behavior across header, delimiter, and body rows. It is
/// a spec-aligned `[fix]` (VT/FF are CommonMark §2.1 whitespace), asserted WITHOUT `.cmarkBugCompatibility`.
@Suite("Table cell pipe-boundary whitespace")
struct TableCellPipeWhitespaceTests {

    private static let ff = "\u{0C}"  // form feed
    private static let vt = "\u{0B}"  // vertical tab

    /// Every row's cell texts, `[header, body1, ...]`, for the first `.table` in the tree; `nil` if none.
    private func tableRows(_ source: String) throws -> [[String]]? {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> [[String]]? in
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
    private func firstBlockKind(_ source: String) throws -> String {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> String in
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

    // MARK: - FIX: FF/VT after a pipe is consumed (not cell content), matching scan_table_cell_end

    @Test("form-feed after an interior header pipe is not part of the next cell")
    func interiorHeaderFormFeed() throws {
        // `a|<FF>b` : cmark's cell_end eats `|<FF>`, so cell 2 is "b" (not "<FF>b").
        let rows = try #require(try tableRows("a|\(Self.ff)b\n-|-"))
        #expect(rows.first == ["a", "b"])
    }

    @Test("form-feed after an interior body pipe is not part of the next cell")
    func interiorBodyFormFeed() throws {
        let rows = try #require(try tableRows("a|b\n-|-\nc|\(Self.ff)d"))
        #expect(rows == [["a", "b"], ["c", "d"]])
    }

    @Test("a trailing pipe then form-feed is a closing pipe on the delimiter row")
    func delimiterTrailingPipeFormFeed() throws {
        // `d\n-|<FF>` : the `|<FF>` is a closing pipe (1-column delimiter), so a table forms.
        let rows = try #require(try tableRows("d\n-|\(Self.ff)"))
        #expect(rows == [["d"]])
    }

    @Test("a trailing pipe then vertical-tab is a closing pipe on the delimiter row")
    func delimiterTrailingPipeVerticalTab() throws {
        let rows = try #require(try tableRows("d\n-|\(Self.vt)"))
        #expect(rows == [["d"]])
    }

    @Test("a trailing pipe then form-feed in the header closes the row (column mismatch, no table)")
    func trailingHeaderPipeFormFeedMismatch() throws {
        // `a|b|<FF>` : the `|<FF>` closes the header at 2 columns; the delimiter `-|-|-` has 3 ⇒ mismatch
        // ⇒ NOT a table (a paragraph). The rewrite previously kept `<FF>` as a spurious 3rd cell.
        #expect(try firstBlockKind("a|b|\(Self.ff)\n-|-|-") == "paragraph")
    }

    // MARK: - LEAVE: guards that must stay correct

    @Test("form-feed BEFORE a pipe stays cell content")
    func formFeedBeforePipeIsContent() throws {
        // `a<FF>|b` : the FF is trailing content of cell 1 (not adjacent-after a pipe); cmark's
        // strbuf_trim (space/tab) keeps it, so cell 1 is "a<FF>".
        let rows = try #require(try tableRows("a\(Self.ff)|b\n-|-"))
        #expect(rows.first == ["a\(Self.ff)", "b"])
    }

    @Test("leading form-feed on a first cell with NO leading pipe stays cell content")
    func leadingFormFeedFirstCellNoPipe() throws {
        // `<FF>a|b` : the first cell is not pipe-preceded, so there is no `scan_table_cell_end`
        // internal_offset to consume the FF; cmark's only trim is strbuf_trim (space/tab), which keeps
        // the leading FF. Cell 1 is "<FF>a" — NOT "a".
        let rows = try #require(try tableRows("\(Self.ff)a|b\n-|-"))
        #expect(rows.first == ["\(Self.ff)a", "b"])
    }

    @Test("leading vertical-tab on a first cell with NO leading pipe stays cell content")
    func leadingVerticalTabFirstCellNoPipe() throws {
        let rows = try #require(try tableRows("\(Self.vt)a|b\n-|-"))
        #expect(rows.first == ["\(Self.vt)a", "b"])
    }

    @Test("leading form-feed on a first cell WITH a leading pipe is consumed")
    func leadingFormFeedFirstCellWithPipe() throws {
        // `|<FF>a|b` : the leading pipe makes cell 1 pipe-preceded, so cmark's cell_end consumes the FF;
        // cell 1 is "a".
        let rows = try #require(try tableRows("|\(Self.ff)a|b\n-|-"))
        #expect(rows.first == ["a", "b"])
    }

    @Test("a trailing pipe then form-feed in a BODY row keeps the row's cells (count tolerated)")
    func trailingBodyPipeFormFeed() throws {
        let rows = try #require(try tableRows("a|b\n-|-\nc|d|\(Self.ff)"))
        #expect(rows == [["a", "b"], ["c", "d"]])
    }

    @Test("a bare trailing pipe still forms a table")
    func bareTrailingPipe() throws {
        let rows = try #require(try tableRows("d\n-|"))
        #expect(rows == [["d"]])
    }

    @Test("an escaped pipe is not a cell separator")
    func escapedPipeNotSeparator() throws {
        // `a\|b` has no unescaped pipe ⇒ 1-column header "a|b"; `-|-` has 2 ⇒ mismatch ⇒ paragraph.
        #expect(try firstBlockKind("a\\|b\n-|-") == "paragraph")
    }
}
