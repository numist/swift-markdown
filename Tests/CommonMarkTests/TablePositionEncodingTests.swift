/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges under multibyte UTF-8 in table cells, `\|`-escaped cells and tab-indented content.
/// Columns count bytes from the line start, plus one.
///
/// Encodings exercised: ASCII, `é` (2 bytes), `€` (3 bytes), `😀` (4 bytes), `e´` (combining,
/// 3 bytes), literal `U+FFFD` (3 bytes), and tab.
@Suite("Table and tab-indented source positions — Unicode encodings")
struct TablePositionEncodingTests {

    typealias Pos = MarkdownNode.SourcePosition

    static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    // MARK: - Helpers

    /// Build a half-open source range from a start (line, column) to an end (line, column).
    private func r(_ sl: Int, _ sc: Int, _ el: Int, _ ec: Int) -> Range<Pos> {
        Pos(line: sl, column: sc)..<Pos(line: el, column: ec)
    }

    private struct Cell {
        let alignment: MarkdownNode.TableAlignment
        let colspan: Int
        let range: Range<Pos>
        /// Concatenated literal text of the cell's inline children.
        let text: String
        /// The first positioned inline child's source range (the cell's Text run).
        let textRange: Range<Pos>?
    }

    private struct Row {
        let isHeader: Bool
        let range: Range<Pos>
        let cells: [Cell]
    }

    /// Rows (header first, then body rows in order) of the first top-level `.table` in `source`.
    /// Each cell carries its span, range, literal text, and the range of its first inline Text run.
    private func tableRows(_ source: String) -> [Row] {
        MarkdownDocument.withParsedDocument(source, options: Self.opts) { doc -> [Row] in
            var rows: [Row] = []
            var found = false
            doc.root.children.forEach { block in
                if found || block.kind != .table { return }
                found = true
                block.children.forEach { row in
                    guard case .tableRow(let isHeader) = row.kind, let rowRange = row.sourceRange else { return }
                    var cells: [Cell] = []
                    row.children.forEach { cell in
                        guard case .tableCell(let alignment, let columns, _) = cell.kind,
                              let range = cell.sourceRange else { return }
                        var text = ""
                        var textRange: Range<Pos>? = nil
                        cell.children.forEach { inline in
                            if let lit = inline.literal() { text += lit }
                            if textRange == nil, let ir = inline.sourceRange { textRange = ir }
                        }
                        cells.append(Cell(alignment: alignment, colspan: columns, range: range, text: text, textRange: textRange))
                    }
                    rows.append(Row(isHeader: isHeader, range: rowRange, cells: cells))
                }
            }
            return rows
        }
    }

    /// Every node's (kind, literal, range) in document order.
    private func nodes(_ source: String) -> [EncNode] {
        MarkdownDocument.withParsedDocument(source, options: Self.opts) { doc -> [EncNode] in
            var out: [EncNode] = []
            dfsEncNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Multi-column tables, multibyte inside cells

    @Test("multi-column: multibyte at a body cell's start counts its bytes")
    func bodyCellMultibyteStart() throws {
        // Body line 3 `éx|y`: é@bytes0-1 (cols1-2), x@byte2 (col3), |@byte3 (col4), y@byte4 (col5).
        let rows = tableRows("a|b\n-|-\n\u{E9}x|y")
        try #require(rows.count == 2, "fixture: header + body row, got \(rows.count)")
        let body = rows[1]
        try #require(body.cells.count == 2, "fixture: two body cells, got \(body.cells.count)")
        try #require(body.cells[0].text == "\u{E9}x" && body.cells[1].text == "y", "fixture: cell literals")
        #expect(body.range == r(3, 1, 3, 6))
        #expect(body.cells[0].range == r(3, 1, 3, 4))       // `éx` ends past x (before the pipe)
        #expect(body.cells[0].textRange == r(3, 1, 3, 4))
        #expect(body.cells[1].range == r(3, 5, 3, 6))       // `y`
        #expect(body.cells[1].textRange == r(3, 5, 3, 6))
    }

    /// `€` (3 bytes) as the whole second body cell: its Text run spans three byte-columns.
    @Test("multi-column: a 3-byte cell spans three byte-columns")
    func bodyCellThreeByte() throws {
        // Body line 3 `x|€`: x@byte0 (col1), |@byte1 (col2), €@bytes2-4 (cols3-5).
        let rows = tableRows("a|b\n-|-\nx|\u{20AC}")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{20AC}", "fixture: `€` cell literal")
        #expect(body.cells[0].range == r(3, 1, 3, 2))       // `x`
        #expect(body.cells[1].range == r(3, 3, 3, 6))       // `€` ends at col6 (past its 3rd byte)
        #expect(body.cells[1].textRange == r(3, 3, 3, 6))
        #expect(body.range == r(3, 1, 3, 6))
    }

    /// `😀` (4 bytes) as the whole second body cell: its Text run spans four byte-columns.
    @Test("multi-column: a 4-byte emoji cell spans four byte-columns")
    func bodyCellEmoji() throws {
        // Body line 3 `x|😀`: x@byte0 (col1), |@byte1 (col2), 😀@bytes2-5 (cols3-6).
        let rows = tableRows("a|b\n-|-\nx|\u{1F600}")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{1F600}", "fixture: emoji cell literal")
        #expect(body.cells[1].range == r(3, 3, 3, 7))       // `😀` ends at col7 (past its 4th byte)
        #expect(body.cells[1].textRange == r(3, 3, 3, 7))
        #expect(body.range == r(3, 1, 3, 7))
    }

    /// A combining sequence (`e` + U+0301, 3 bytes) inside a cell: columns count bytes, not grapheme
    /// clusters.
    @Test("multi-column: a combining sequence in a cell counts its bytes")
    func bodyCellCombining() throws {
        // Body line 3 `e´x|y`: e@byte0 (col1), U+0301@bytes1-2 (cols2-3), x@byte3 (col4).
        let rows = tableRows("a|b\n-|-\ne\u{301}x|y")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[0].text == "e\u{301}x", "fixture: combining cell literal")
        #expect(body.cells[0].range == r(3, 1, 3, 5))       // `e´x` ends past x
        #expect(body.cells[0].textRange == r(3, 1, 3, 5))
        #expect(body.cells[1].range == r(3, 6, 3, 7))       // `y`
        #expect(body.range == r(3, 1, 3, 7))
    }

    /// A U+FFFD written in the source, rather than replacing a NUL, counts its three bytes.
    @Test("multi-column: a literal U+FFFD cell counts three byte-columns")
    func bodyCellReplacementChar() throws {
        // Body line 3 `x|�`: x@byte0 (col1), |@byte1 (col2), U+FFFD@bytes2-4 (cols3-5).
        let rows = tableRows("a|b\n-|-\nx|\u{FFFD}")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{FFFD}", "fixture: U+FFFD cell literal")
        #expect(body.cells[1].range == r(3, 3, 3, 6))       // `�` ends at col6
        #expect(body.cells[1].textRange == r(3, 3, 3, 6))
    }

    /// Multibyte in the middle column of a three-column row shifts the cells to its right by its byte
    /// width.
    @Test("multi-column: multibyte in the middle column shifts the right column by its byte width")
    func middleColumnMultibyte() throws {
        // Body line 3 `x|é|z`: x@byte0 (col1), |@byte1 (col2), é@bytes2-3 (cols3-4), |@byte4 (col5), z@byte5 (col6).
        let rows = tableRows("a|b|c\n-|-|-\nx|\u{E9}|z")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 3 && body.cells.map(\.text) == ["x", "\u{E9}", "z"], "fixture: three cells")
        #expect(body.cells[0].range == r(3, 1, 3, 2))       // `x`
        #expect(body.cells[1].range == r(3, 3, 3, 5))       // `é`
        #expect(body.cells[1].textRange == r(3, 3, 3, 5))
        #expect(body.cells[2].range == r(3, 6, 3, 7))       // `z` (pushed one col right by é's 2nd byte)
        #expect(body.range == r(3, 1, 3, 7))
    }

    /// Multibyte in the header row widens the header's cell, Text and row ranges by its bytes.
    @Test("multi-column: multibyte in the header widens the header ranges")
    func headerMultibyte() throws {
        // Header line 1 `€x|y`: €@bytes0-2 (cols1-3), x@byte3 (col4), |@byte4 (col5), y@byte5 (col6).
        let rows = tableRows("\u{20AC}x|y\n-|-\nc|d")
        try #require(rows.count == 2, "fixture: header + body row")
        let head = rows[0]
        try #require(head.isHeader && head.cells.count == 2 && head.cells[0].text == "\u{20AC}x", "fixture: header cells")
        #expect(head.range == r(1, 1, 1, 7))                // Head spans the whole header content
        #expect(head.cells[0].range == r(1, 1, 1, 5))       // `€x` ends before the pipe
        #expect(head.cells[0].textRange == r(1, 1, 1, 5))
        #expect(head.cells[1].range == r(1, 6, 1, 7))       // `y`
        #expect(rows[1].cells.map(\.range) == [r(3, 1, 3, 2), r(3, 3, 3, 4)])
    }

    /// Each row's columns come from its own bytes.
    @Test("multi-column: independent multibyte in header and body")
    func headerAndBodyMultibyte() throws {
        // Header `é|b`: é@cols1-2, |@col3, b@col4. Body `c|€`: c@col1, |@col2, €@cols3-5.
        let rows = tableRows("\u{E9}|b\n-|-\nc|\u{20AC}")
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[0].cells.map(\.text) == ["\u{E9}", "b"] && rows[1].cells.map(\.text) == ["c", "\u{20AC}"],
                     "fixture: cell literals")
        // Header
        #expect(rows[0].range == r(1, 1, 1, 5))
        #expect(rows[0].cells[0].range == r(1, 1, 1, 3))    // `é`
        #expect(rows[0].cells[1].range == r(1, 4, 1, 5))    // `b`
        // Body
        #expect(rows[1].range == r(3, 1, 3, 6))
        #expect(rows[1].cells[0].range == r(3, 1, 3, 2))    // `c`
        #expect(rows[1].cells[1].range == r(3, 3, 3, 6))    // `€`
        #expect(rows[1].cells[1].textRange == r(3, 3, 3, 6))
    }

    // MARK: - Single-column tables, multibyte

    /// A single-column table (delimiter `|-`) with multibyte in the header and the body.
    @Test("single-column: multibyte header and body cells")
    func singleColumnMultibyte() throws {
        // Header line 1 `é`: cols1-3 (2 bytes). Body line 3 `€`: cols1-4 (3 bytes).
        let rows = tableRows("\u{E9}\n|-\n\u{20AC}")
        try #require(rows.count == 2, "fixture: header + body row, got \(rows.count)")
        try #require(rows[0].cells.count == 1 && rows[1].cells.count == 1, "fixture: one column")
        try #require(rows[0].cells[0].text == "\u{E9}" && rows[1].cells[0].text == "\u{20AC}", "fixture: literals")
        #expect(rows[0].range == r(1, 1, 1, 3))
        #expect(rows[0].cells[0].range == r(1, 1, 1, 3))    // `é`
        #expect(rows[0].cells[0].textRange == r(1, 1, 1, 3))
        #expect(rows[1].range == r(3, 1, 3, 4))
        #expect(rows[1].cells[0].range == r(3, 1, 3, 4))    // `€`
        #expect(rows[1].cells[0].textRange == r(3, 1, 3, 4))
    }

    /// A single-column body row written with a leading pipe (`|€`): the pipe occupies col1, so the cell
    /// content starts at col2.
    @Test("single-column: leading-pipe body cell with multibyte")
    func singleColumnLeadingPipeMultibyte() throws {
        // Body line 3 `|€`: |@byte0 (col1), €@bytes1-3 (cols2-4).
        let rows = tableRows("a\n|-\n|\u{20AC}")
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[1].cells.count == 1 && rows[1].cells[0].text == "\u{20AC}", "fixture: `€` body cell")
        #expect(rows[1].range == r(3, 1, 3, 5))
        #expect(rows[1].cells[0].range == r(3, 2, 3, 5))    // `€` after the leading pipe
        #expect(rows[1].cells[0].textRange == r(3, 2, 3, 5))
    }

    // MARK: - \|-escaped cells, multibyte around the escaped pipe

    /// The Text run's source range covers the cell's content bytes, escaping backslash included, so it ends where
    /// the cell does.
    @Test("escaped pipe: \\|-escaped header cell counts the bytes around the pipe")
    func escapedPipeHeaderCellMultibyte() throws {
        // Header line 1 `é\|€|c`: é@bytes0-1 (cols1-2), \@byte2 (col3), |@byte3 (col4),
        // €@bytes4-6 (cols5-7), |@byte7 (col8, cell separator), c@byte8 (col9).
        let rows = tableRows("\u{E9}\\|\u{20AC}|c\n-|-")
        try #require(rows.count == 1, "fixture: header-only table, got \(rows.count) rows")
        let head = rows[0]
        try #require(head.cells.count == 2 && head.cells[0].text == "\u{E9}|\u{20AC}" && head.cells[1].text == "c",
                     "fixture: escaped-pipe cell literal `é|€`")
        #expect(head.cells[0].range == r(1, 1, 1, 8))       // cell ends at the separator pipe (col8)
        #expect(head.cells[0].textRange == r(1, 1, 1, 8))
        #expect(head.cells[1].range == r(1, 9, 1, 10))      // `c`
        #expect(head.cells[1].textRange == r(1, 9, 1, 10))
        #expect(head.range == r(1, 1, 1, 10))
    }

    @Test("escaped pipe: \\|-escaped header cell counts a 4-byte emoji")
    func escapedPipeHeaderCellEmoji() throws {
        // Header line 1 `x\|😀|y`: x@byte0 (col1), \@byte1 (col2), |@byte2 (col3),
        // 😀@bytes3-6 (cols4-7), |@byte7 (col8), y@byte8 (col9).
        let rows = tableRows("x\\|\u{1F600}|y\n-|-")
        try #require(rows.count == 1, "fixture: header-only table")
        let head = rows[0]
        try #require(head.cells.count == 2 && head.cells[0].text == "x|\u{1F600}" && head.cells[1].text == "y",
                     "fixture: escaped-pipe cell literal `x|😀`")
        #expect(head.cells[0].range == r(1, 1, 1, 8))       // cell ends at the separator pipe
        #expect(head.cells[0].textRange == r(1, 1, 1, 8))
        #expect(head.cells[1].range == r(1, 9, 1, 10))      // `y`
    }

    @Test("escaped pipe: \\|-escaped body cell counts the bytes around the pipe")
    func escapedPipeBodyCellMultibyte() throws {
        // Body line 3 `é\|€|c`, same byte layout as the header case.
        let rows = tableRows("a|b\n-|-\n\u{E9}\\|\u{20AC}|c")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[0].text == "\u{E9}|\u{20AC}" && body.cells[1].text == "c",
                     "fixture: escaped-pipe body cell literal `é|€`")
        #expect(body.cells[0].range == r(3, 1, 3, 8))       // cell ends at the separator pipe
        #expect(body.cells[0].textRange == r(3, 1, 3, 8))
        #expect(body.cells[1].range == r(3, 9, 3, 10))      // `c`
        #expect(body.cells[1].textRange == r(3, 9, 3, 10))
        #expect(body.range == r(3, 1, 3, 10))
    }

    // MARK: - Tab-indented content, multibyte

    @Test("tab: list-item content after a tab maps back to its source byte column")
    func listItemContentAfterTab() throws {
        // Line 1 `-\téx`: -@byte0 (col1), \t@byte1 (col2), é@bytes2-3 (cols3-4), x@byte4 (col5).
        let nodes = nodes("-\t\u{E9}x")
        let para = nodes.first { $0.kind == .paragraph }
        let text = nodes.first { $0.kind == .text }
        try #require(text?.literal == "\u{E9}x", "fixture: item paragraph text `éx`")
        #expect(para?.range == r(1, 3, 1, 6))               // content starts at col3 (after `-` + tab)
        #expect(text?.range == r(1, 3, 1, 6))               // `éx` ends past x
    }

    @Test("tab: indented code block, leading tab + multibyte body")
    func indentedCodeLeadingTab() throws {
        // Line 1 `\tcodeé`: \t@byte0 (col1, the indent), c@byte1 (col2) … é@bytes5-6 (cols6-7).
        let nodes = nodes("\tcode\u{E9}")
        let code = nodes.first { $0.kind == .indentedCode }
        // The literal's trailing line ending is not in the source, so the range ends after `é`.
        try #require(code?.literal == "code\u{E9}\n", "fixture: code body `codeé`")
        #expect(code?.range == r(1, 2, 1, 8))               // body starts at col2, ends past é (col8)
    }

    @Test("tab: indented code block, interior tab kept literally + multibyte")
    func indentedCodeInteriorTab() throws {
        // Line 1 `\tco\tdeé`: \t@byte0 (indent), c@byte1, o@byte2, \t@byte3 (interior, kept),
        // d@byte4, e@byte5, é@bytes6-7 (cols7-8).
        let nodes = nodes("\tco\tde\u{E9}")
        let code = nodes.first { $0.kind == .indentedCode }
        try #require(code?.literal == "co\tde\u{E9}\n", "fixture: code body keeps the interior tab")
        #expect(code?.range == r(1, 2, 1, 9))               // body starts at col2, ends past é (col9)
    }

    @Test("tab: indented code block, excess leading tab becomes a body byte")
    func indentedCodeExcessTab() throws {
        // Line 1 `\t\tcodeé`: \t@byte0 (indent), \t@byte1 (residual, kept in body), c@byte2 … é@bytes6-7.
        let nodes = nodes("\t\tcode\u{E9}")
        let code = nodes.first { $0.kind == .indentedCode }
        try #require(code?.literal == "\tcode\u{E9}\n", "fixture: body keeps the second (residual) tab")
        #expect(code?.range == r(1, 2, 1, 9))               // body starts at col2 (after the first tab)
    }

    @Test("tab: indented code block, spaces then a tab complete the indent")
    func indentedCodeSpacesThenTab() throws {
        // Line 1 `  \tcodeé`: space@byte0 (col1), space@byte1 (col2), \t@byte2 (col3, completes the
        // 4-col indent), c@byte3 (col4) … é@bytes7-8 (cols8-9).
        let nodes = nodes("  \tcode\u{E9}")
        let code = nodes.first { $0.kind == .indentedCode }
        try #require(code?.literal == "code\u{E9}\n", "fixture: code body `codeé`, no residual whitespace")
        #expect(code?.range == r(1, 4, 1, 10))              // body starts at col4, ends past é (col10)
    }

    @Test("tab: list-item content after a tab, with an interior tab + multibyte")
    func listItemAfterTabInteriorTab() throws {
        // Line 1 `-\téx\ty`: -@byte0 (col1), \t@byte1 (col2), é@bytes2-3 (cols3-4), x@byte4 (col5),
        // \t@byte5 (col6, interior), y@byte6 (col7).
        let nodes = nodes("-\t\u{E9}x\ty")
        let text = nodes.first { $0.kind == .text }
        try #require(text?.literal == "\u{E9}x\ty", "fixture: item text keeps the interior tab")
        #expect(text?.range == r(1, 3, 1, 8))               // content @col3, ends past y (col8)
    }

    // MARK: - Leading whitespace

    @Test("an indented multibyte body row's cells start after its leading whitespace")
    func leadingWhitespaceBodyRowMultibyte() throws {
        // Body line 3 ` éx|y`: space@byte0 (col1), é@bytes1-2 (cols2-3), x@byte3 (col4), |@byte4 (col5),
        // y@byte5 (col6).
        let rows = tableRows("a|b\n-|-\n \u{E9}x|y")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells.allSatisfy { $0.range.lowerBound.column > 0 },
                     "fixture: cells must have source ranges")
        try #require(body.cells[0].text == "\u{E9}x" && body.cells[1].text == "y", "fixture: cell literals")
        #expect(body.range == r(3, 2, 3, 7))
        #expect(body.cells[0].range == r(3, 2, 3, 5))       // `éx`
        #expect(body.cells[0].textRange == r(3, 2, 3, 5))
        #expect(body.cells[1].range == r(3, 6, 3, 7))       // `y`
    }

    @Test("an indented multibyte header row does not shift an unindented body row")
    func leadingWhitespaceHeaderMultibyte() throws {
        // Header line 1 ` é|b`: space@byte0 (col1), é@bytes1-2 (cols2-3), |@byte3 (col4), b@byte4 (col5).
        // Body line 3 `x|y`: x@byte0 (col1), |@byte1 (col2), y@byte2 (col3).
        let rows = tableRows(" \u{E9}|b\n-|-\nx|y")
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[0].cells.count == 2 && rows[1].cells.count == 2, "fixture: two cells per row")
        try #require(rows[0].cells[0].text == "\u{E9}" && rows[1].cells.map(\.text) == ["x", "y"], "fixture: literals")
        #expect(rows[0].range == r(1, 2, 1, 6))
        #expect(rows[0].cells[0].range == r(1, 2, 1, 4))    // `é`
        #expect(rows[0].cells[1].range == r(1, 5, 1, 6))    // `b`
        #expect(rows[1].range == r(3, 1, 3, 4))
        #expect(rows[1].cells[0].range == r(3, 1, 3, 2))    // `x`
        #expect(rows[1].cells[1].range == r(3, 3, 3, 4))    // `y`
    }

    /// The continuation line's leading tab is stripped from the paragraph's content (Paragraphs), so its
    /// Text run starts after the tab.
    @Test("a tab-indented multibyte paragraph continuation line starts after its tab")
    func paragraphContinuationLeadingTab() throws {
        // Line 1 `foo`, line 2 `\tbar€`: \t@byte0 (col1), b@byte1 (col2) … €@bytes4-6 (cols5-7).
        let nodes = nodes("foo\n\tbar\u{20AC}")
        let para = nodes.first { $0.kind == .paragraph }
        let texts = nodes.filter { $0.kind == .text }
        try #require(texts.count == 2 && texts[0].literal == "foo" && texts[1].literal == "bar\u{20AC}",
                     "fixture: two text runs `foo` / `bar€`")
        #expect(para?.range == r(1, 1, 2, 8))
        #expect(texts[0].range == r(1, 1, 1, 4))            // `foo`
        #expect(texts[1].range == r(2, 2, 2, 8))            // `bar€`
    }
}

/// A node's kind, its literal text (if any), and its source range. File-scope because a recursive walk
/// over `borrowing MarkdownNode` can't be an instance-method closure.
private struct EncNode {
    let kind: MarkdownNode.Kind
    let literal: String?
    let range: Range<MarkdownNode.SourcePosition>?
}

private func dfsEncNodes(_ node: borrowing MarkdownNode, into out: inout [EncNode]) {
    out.append(EncNode(kind: node.kind, literal: node.literal(), range: node.sourceRange))
    node.children.forEach { child in dfsEncNodes(child, into: &out) }
}
