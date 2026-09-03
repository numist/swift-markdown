/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source-position coverage for the two highest-risk stamping paths under multibyte Unicode:
/// GFM **table cells** and **arena/materialized** content (tab-expanded lines, `\|`-escaped cells).
/// Both are inline-parsed from an arena copy whose byte offsets are re-mapped back to the source
/// (`ArenaRun`), so a multibyte character or a tab is exactly where that remap could drift.
///
/// Columns are 1-based UTF-8 **byte** offsets; `upperBound.column` is half-open (one past the node's
/// last byte). Every asserted value is the DELIVERABLE (flag-OFF) surface, cross-checked against
/// `dump --new-off <input, trailing 0x00>` and reasoned from the byte layout. Where the deliverable
/// diverges from cmark-gfm, the divergence is a documented Quirk-E-family re-index quirk (the leading-
/// whitespace table-row re-base and the paragraph continuation re-indent) — the deliverable keeps the
/// SPEC-CORRECT physical byte column while cmark discards the leading whitespace. Those cases assert the
/// flag-OFF value and flag the divergence with a `// cmark differs` comment.
///
/// Encoding classes exercised: ASCII, `é` (2 bytes), `€` (3 bytes), `😀` (4 bytes), `e´` (combining,
/// 3 bytes), literal `U+FFFD` (3 bytes), and TAB.
@Suite("Table & arena source positions — Unicode encodings")
struct TablePositionEncodingTests {

    typealias Pos = MarkdownNode.SourcePosition

    /// The deliverable option set: exactly what the Markdown wrapper (and `dump --new-off`, options
    /// byte 0x00) enables — GFM tables + spans + strikethrough + tasklist, smart punctuation, and
    /// source positions. NO `.cmarkBugCompatibility`, so this is the shipped, spec-correct surface.
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
        /// The first positioned inline child's source range (the cell's Text run), stamped by the
        /// inline pass — a separate path from the cell node's own range.
        let textRange: Range<Pos>?
    }

    private struct Row {
        let isHeader: Bool
        let range: Range<Pos>
        let cells: [Cell]
    }

    /// Rows (header first, then body rows in order) of the first top-level `.table` in `source`,
    /// parsed with the deliverable options. Each cell carries its span, range, literal text, and the
    /// range of its first inline Text run. Fixed table depth, so plain `.forEach` (no recursion).
    private func tableRows(_ source: String) throws -> [Row] {
        try MarkdownDocument.withParsedDocument(source, options: Self.opts) { doc -> [Row] in
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

    /// DFS-collect every node's (kind, literal, range) in document order — used for the non-table
    /// arena/tab cases (list items, code blocks, paragraph continuations).
    private func nodes(_ source: String) throws -> [EncNode] {
        try MarkdownDocument.withParsedDocument(source, options: Self.opts) { doc -> [EncNode] in
            var out: [EncNode] = []
            dfsEncNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Multi-column tables, multibyte inside cells (contiguous zero-copy path)

    /// `éx` in the first body cell: `é` is 2 bytes, so the cell/Text run ends one byte later than an
    /// ASCII cell would. Matches cmark and is byte-exact.
    @Test("multi-column: multibyte at a body cell's start remaps to true byte columns")
    func bodyCellMultibyteStart() throws {
        // Body line 3 `éx|y`: é@bytes0-1 (cols1-2), x@byte2 (col3), |@byte3 (col4), y@byte4 (col5).
        let rows = try tableRows("a|b\n-|-\n\u{E9}x|y")
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
        let rows = try tableRows("a|b\n-|-\nx|\u{20AC}")
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
        let rows = try tableRows("a|b\n-|-\nx|\u{1F600}")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{1F600}", "fixture: emoji cell literal")
        #expect(body.cells[1].range == r(3, 3, 3, 7))       // `😀` ends at col7 (past its 4th byte)
        #expect(body.cells[1].textRange == r(3, 3, 3, 7))
        #expect(body.range == r(3, 1, 3, 7))
    }

    /// A combining sequence (`e` + U+0301, 3 bytes) inside a cell: the base + combining mark contribute
    /// three byte-columns, `x` a fourth. cmark and the rewrite both count bytes, not grapheme clusters.
    @Test("multi-column: a combining sequence in a cell counts its bytes")
    func bodyCellCombining() throws {
        // Body line 3 `e´x|y`: e@byte0 (col1), U+0301@bytes1-2 (cols2-3), x@byte3 (col4).
        let rows = try tableRows("a|b\n-|-\ne\u{301}x|y")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[0].text == "e\u{301}x", "fixture: combining cell literal")
        #expect(body.cells[0].range == r(3, 1, 3, 5))       // `e´x` ends past x
        #expect(body.cells[0].textRange == r(3, 1, 3, 5))
        #expect(body.cells[1].range == r(3, 6, 3, 7))       // `y`
        #expect(body.range == r(3, 1, 3, 7))
    }

    /// A literal U+FFFD (3 bytes) already present in the source (NOT a NUL replacement) is passed through
    /// and counted as three byte-columns.
    @Test("multi-column: a literal U+FFFD cell counts three byte-columns")
    func bodyCellReplacementChar() throws {
        // Body line 3 `x|�`: x@byte0 (col1), |@byte1 (col2), U+FFFD@bytes2-4 (cols3-5).
        let rows = try tableRows("a|b\n-|-\nx|\u{FFFD}")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{FFFD}", "fixture: U+FFFD cell literal")
        #expect(body.cells[1].range == r(3, 3, 3, 6))       // `�` ends at col6
        #expect(body.cells[1].textRange == r(3, 3, 3, 6))
    }

    /// Multibyte in the MIDDLE column of a three-column row: the columns to its right must be pushed by
    /// the multibyte width, not by a fixed per-cell stride.
    @Test("multi-column: multibyte in the middle column shifts the right column by its byte width")
    func middleColumnMultibyte() throws {
        // Body line 3 `x|é|z`: x@byte0 (col1), |@byte1 (col2), é@bytes2-3 (cols3-4), |@byte4 (col5), z@byte5 (col6).
        let rows = try tableRows("a|b|c\n-|-|-\nx|\u{E9}|z")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 3 && body.cells.map(\.text) == ["x", "\u{E9}", "z"], "fixture: three cells")
        #expect(body.cells[0].range == r(3, 1, 3, 2))       // `x`
        #expect(body.cells[1].range == r(3, 3, 3, 5))       // `é`
        #expect(body.cells[1].textRange == r(3, 3, 3, 5))
        #expect(body.cells[2].range == r(3, 6, 3, 7))       // `z` (pushed one col right by é's 2nd byte)
        #expect(body.range == r(3, 1, 3, 7))
    }

    /// Multibyte in the HEADER row: the header cell/Text/Head ranges all widen by the multibyte bytes.
    @Test("multi-column: multibyte in the header widens the header ranges")
    func headerMultibyte() throws {
        // Header line 1 `€x|y`: €@bytes0-2 (cols1-3), x@byte3 (col4), |@byte4 (col5), y@byte5 (col6).
        let rows = try tableRows("\u{20AC}x|y\n-|-\nc|d")
        try #require(rows.count == 2, "fixture: header + body row")
        let head = rows[0]
        try #require(head.isHeader && head.cells.count == 2 && head.cells[0].text == "\u{20AC}x", "fixture: header cells")
        #expect(head.range == r(1, 1, 1, 7))                // Head spans the whole header content
        #expect(head.cells[0].range == r(1, 1, 1, 5))       // `€x` ends before the pipe
        #expect(head.cells[0].textRange == r(1, 1, 1, 5))
        #expect(head.cells[1].range == r(1, 6, 1, 7))       // `y`
        // Body row is unaffected ASCII.
        #expect(rows[1].cells.map(\.range) == [r(3, 1, 3, 2), r(3, 3, 3, 4)])
    }

    /// Multibyte in BOTH the header and the body: each row's columns are computed independently from its
    /// own bytes.
    @Test("multi-column: independent multibyte in header and body")
    func headerAndBodyMultibyte() throws {
        // Header `é|b`: é@cols1-2, |@col3, b@col4. Body `c|€`: c@col1, |@col2, €@cols3-5.
        let rows = try tableRows("\u{E9}|b\n-|-\nc|\u{20AC}")
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
        let rows = try tableRows("\u{E9}\n|-\n\u{20AC}")
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
        let rows = try tableRows("a\n|-\n|\u{20AC}")
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[1].cells.count == 1 && rows[1].cells[0].text == "\u{20AC}", "fixture: `€` body cell")
        #expect(rows[1].range == r(3, 1, 3, 5))
        #expect(rows[1].cells[0].range == r(3, 2, 3, 5))    // `€` after the leading pipe
        #expect(rows[1].cells[0].textRange == r(3, 2, 3, 5))
    }

    // MARK: - \|-escaped cells (arena-copy path), multibyte around the escaped pipe

    /// A `\|`-escaped cell takes the arena-copy path: `unescapePipes` strips the backslash, so the cell's
    /// inline runs are parsed from an arena copy and mapped back by a CONSTANT delta. cmark maps this
    /// escape-obliviously (it does NOT re-widen the removed backslash), so the Text run's END lands one
    /// byte short of the true source end — the rewrite reproduces cmark's constant-delta mapping exactly
    /// (unconditional, FINDINGS #11/#13). This case pins that the multibyte around the escaped pipe still
    /// survives the arena→source remap.
    @Test("arena: \\|-escaped header cell keeps multibyte through the arena remap")
    func escapedPipeHeaderCellMultibyte() throws {
        // Header line 1 `é\|€|c`: é@bytes0-1 (cols1-2), \@byte2 (col3), |@byte3 (col4),
        // €@bytes4-6 (cols5-7), |@byte7 (col8, cell separator), c@byte8 (col9).
        let rows = try tableRows("\u{E9}\\|\u{20AC}|c\n-|-")
        try #require(rows.count == 1, "fixture: header-only table, got \(rows.count) rows")
        let head = rows[0]
        try #require(head.cells.count == 2 && head.cells[0].text == "\u{E9}|\u{20AC}" && head.cells[1].text == "c",
                     "fixture: escaped-pipe cell literal `é|€`")
        #expect(head.cells[0].range == r(1, 1, 1, 8))       // cell ends at the separator pipe (col8)
        // Text run: escape-oblivious end at col7 (arena end mapped by a delta of 0), NOT the byte-true
        // col8 — this matches cmark by design.  // cmark differs: n/a (rewrite reproduces cmark here)
        #expect(head.cells[0].textRange == r(1, 1, 1, 7))
        #expect(head.cells[1].range == r(1, 9, 1, 10))      // `c`
        #expect(head.cells[1].textRange == r(1, 9, 1, 10))
        #expect(head.range == r(1, 1, 1, 10))
    }

    /// The same arena path with a 4-byte emoji after the escaped pipe: the emoji's four bytes are carried
    /// through the arena copy unchanged, so only the removed backslash shifts the constant delta.
    @Test("arena: \\|-escaped header cell keeps a 4-byte emoji through the arena remap")
    func escapedPipeHeaderCellEmoji() throws {
        // Header line 1 `x\|😀|y`: x@byte0 (col1), \@byte1 (col2), |@byte2 (col3),
        // 😀@bytes3-6 (cols4-7), |@byte7 (col8), y@byte8 (col9).
        let rows = try tableRows("x\\|\u{1F600}|y\n-|-")
        try #require(rows.count == 1, "fixture: header-only table")
        let head = rows[0]
        try #require(head.cells.count == 2 && head.cells[0].text == "x|\u{1F600}" && head.cells[1].text == "y",
                     "fixture: escaped-pipe cell literal `x|😀`")
        #expect(head.cells[0].range == r(1, 1, 1, 8))       // cell ends at the separator pipe
        #expect(head.cells[0].textRange == r(1, 1, 1, 7))   // escape-oblivious end (matches cmark)
        #expect(head.cells[1].range == r(1, 9, 1, 10))      // `y`
    }

    /// The arena path exercised on a BODY row rather than the header, with multibyte around the escaped
    /// pipe.
    @Test("arena: \\|-escaped body cell keeps multibyte through the arena remap")
    func escapedPipeBodyCellMultibyte() throws {
        // Body line 3 `é\|€|c`, same byte layout as the header case.
        let rows = try tableRows("a|b\n-|-\n\u{E9}\\|\u{20AC}|c")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[0].text == "\u{E9}|\u{20AC}" && body.cells[1].text == "c",
                     "fixture: escaped-pipe body cell literal `é|€`")
        #expect(body.cells[0].range == r(3, 1, 3, 8))       // cell ends at the separator pipe
        #expect(body.cells[0].textRange == r(3, 1, 3, 7))   // escape-oblivious end (matches cmark)
        #expect(body.cells[1].range == r(3, 9, 3, 10))      // `c`
        #expect(body.cells[1].textRange == r(3, 9, 3, 10))
        #expect(body.range == r(3, 1, 3, 10))
    }

    // MARK: - Tab-materialized content, multibyte (matches cmark, byte-exact)

    /// A list item whose content follows a TAB after the marker: the content is materialized (the tab is
    /// expanded in an arena), yet the inline Text run maps back to its TRUE source byte column.
    @Test("tab: list-item content after a tab maps back to its source byte column")
    func listItemContentAfterTab() throws {
        // Line 1 `-\téx`: -@byte0 (col1), \t@byte1 (col2), é@bytes2-3 (cols3-4), x@byte4 (col5).
        let nodes = try nodes("-\t\u{E9}x")
        let para = nodes.first { $0.kind == .paragraph }
        let text = nodes.first { $0.kind == .text }
        try #require(text?.literal == "\u{E9}x", "fixture: item paragraph text `éx`")
        #expect(para?.range == r(1, 3, 1, 6))               // content starts at col3 (after `-` + tab)
        #expect(text?.range == r(1, 3, 1, 6))               // `éx` ends past x
    }

    /// An indented code block whose leading tab supplies exactly the 4-column indent, with multibyte in
    /// the body: the body starts at the byte after the tab and its end counts the multibyte bytes.
    @Test("tab: indented code block, leading tab + multibyte body")
    func indentedCodeLeadingTab() throws {
        // Line 1 `\tcodeé`: \t@byte0 (col1, the indent), c@byte1 (col2) … é@bytes5-6 (cols6-7).
        let nodes = try nodes("\tcode\u{E9}")
        let code = nodes.first { $0.kind.isCodeBlock }
        // Code-block bodies carry a synthesized trailing newline (not a source byte, so the range ends
        // at é).
        try #require(code?.literal == "code\u{E9}\n", "fixture: code body `codeé`")
        #expect(code?.range == r(1, 2, 1, 8))               // body starts at col2, ends past é (col8)
    }

    /// An indented code block with an INTERIOR tab (kept literally in the body) plus multibyte: the
    /// interior tab counts as a single byte-column, and the multibyte tail counts its bytes.
    @Test("tab: indented code block, interior tab kept literally + multibyte")
    func indentedCodeInteriorTab() throws {
        // Line 1 `\tco\tdeé`: \t@byte0 (indent), c@byte1, o@byte2, \t@byte3 (interior, kept),
        // d@byte4, e@byte5, é@bytes6-7 (cols7-8).
        let nodes = try nodes("\tco\tde\u{E9}")
        let code = nodes.first { $0.kind.isCodeBlock }
        try #require(code?.literal == "co\tde\u{E9}\n", "fixture: code body keeps the interior tab")
        #expect(code?.range == r(1, 2, 1, 9))               // body starts at col2, ends past é (col9)
    }

    /// An indented code block whose leading indent is TWO tabs: the first tab is the 4-column indent, the
    /// second becomes a residual tab in the body. Positions still track true source bytes.
    @Test("tab: indented code block, excess leading tab becomes a body byte")
    func indentedCodeExcessTab() throws {
        // Line 1 `\t\tcodeé`: \t@byte0 (indent), \t@byte1 (residual, kept in body), c@byte2 … é@bytes6-7.
        let nodes = try nodes("\t\tcode\u{E9}")
        let code = nodes.first { $0.kind.isCodeBlock }
        try #require(code?.literal == "\tcode\u{E9}\n", "fixture: body keeps the second (residual) tab")
        #expect(code?.range == r(1, 2, 1, 9))               // body starts at col2 (after the first tab)
    }

    /// An indented code block indented by two spaces + a tab (the tab completes the 4-column indent): the
    /// body starts at the byte after the tab, with no residual whitespace, and counts its multibyte tail.
    @Test("tab: indented code block, spaces then a tab complete the indent")
    func indentedCodeSpacesThenTab() throws {
        // Line 1 `  \tcodeé`: space@byte0 (col1), space@byte1 (col2), \t@byte2 (col3, completes the
        // 4-col indent), c@byte3 (col4) … é@bytes7-8 (cols8-9).
        let nodes = try nodes("  \tcode\u{E9}")
        let code = nodes.first { $0.kind.isCodeBlock }
        try #require(code?.literal == "code\u{E9}\n", "fixture: code body `codeé`, no residual whitespace")
        #expect(code?.range == r(1, 4, 1, 10))              // body starts at col4, ends past é (col10)
    }

    /// A list item after a tab whose content also contains an interior tab, with multibyte: both the
    /// content start (after the marker tab) and the interior tab count true source bytes.
    @Test("tab: list-item content after a tab, with an interior tab + multibyte")
    func listItemAfterTabInteriorTab() throws {
        // Line 1 `-\téx\ty`: -@byte0 (col1), \t@byte1 (col2), é@bytes2-3 (cols3-4), x@byte4 (col5),
        // \t@byte5 (col6, interior), y@byte6 (col7).
        let nodes = try nodes("-\t\u{E9}x\ty")
        let text = nodes.first { $0.kind == .text }
        try #require(text?.literal == "\u{E9}x\ty", "fixture: item text keeps the interior tab")
        #expect(text?.range == r(1, 3, 1, 8))               // content @col3, ends past y (col8)
    }

    // MARK: - Divergences: flag-OFF spec-correct, cmark differs (Quirk-E-family re-index)

    /// A body row with LEADING whitespace, with multibyte content. The deliverable keeps the row's TRUE
    /// PHYSICAL columns (the leading space is visible); cmark re-bases the cells to the table's start
    /// column, making the leading whitespace invisible. Assert the spec-correct flag-OFF value.
    @Test("divergence: a leading-whitespace body row keeps physical columns under multibyte")
    func leadingWhitespaceBodyRowMultibyte() throws {
        // Body line 3 ` éx|y`: space@byte0 (col1), é@bytes1-2 (cols2-3), x@byte3 (col4), |@byte4 (col5),
        // y@byte5 (col6).
        let rows = try tableRows("a|b\n-|-\n \u{E9}x|y")
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells.allSatisfy { $0.range.lowerBound.column > 0 },
                     "fixture: leading-ws cells must be positioned, not dropped")
        try #require(body.cells[0].text == "\u{E9}x" && body.cells[1].text == "y", "fixture: cell literals")
        // cmark differs: re-bases to the table start column — `éx`@3:1-3:4, `y`@3:5-3:6, Row@3:1 (leading
        // space invisible) — Quirk E family (leading-whitespace table-row re-base, FINDINGS #64/#71).
        #expect(body.range == r(3, 2, 3, 7))                // physical: row content starts at col2
        #expect(body.cells[0].range == r(3, 2, 3, 5))       // `éx` at its true column (space visible)
        #expect(body.cells[0].textRange == r(3, 2, 3, 5))
        #expect(body.cells[1].range == r(3, 6, 3, 7))       // `y`
    }

    /// A leading-whitespace HEADER (with multibyte) sets cmark's table start column, which cmark then
    /// re-bases every row to — INCLUDING an unindented body row. The deliverable agrees on the header's
    /// own physical columns but keeps the body row at its own true (unindented) columns. Assert flag-OFF.
    @Test("divergence: a leading-whitespace multibyte header does not re-base an unindented body row")
    func leadingWhitespaceHeaderMultibyte() throws {
        // Header line 1 ` é|b`: space@byte0 (col1), é@bytes1-2 (cols2-3), |@byte3 (col4), b@byte4 (col5).
        // Body line 3 `x|y`: x@byte0 (col1), |@byte1 (col2), y@byte2 (col3).
        let rows = try tableRows(" \u{E9}|b\n-|-\nx|y")
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[0].cells.count == 2 && rows[1].cells.count == 2, "fixture: two cells per row")
        try #require(rows[0].cells[0].text == "\u{E9}" && rows[1].cells.map(\.text) == ["x", "y"], "fixture: literals")
        // Header: both the deliverable and cmark keep the header's physical columns (é@1:2).
        #expect(rows[0].range == r(1, 2, 1, 6))
        #expect(rows[0].cells[0].range == r(1, 2, 1, 4))    // `é`
        #expect(rows[0].cells[1].range == r(1, 5, 1, 6))    // `b`
        // Body: cmark differs: re-bases the unindented body row to the header's start column —
        // `x`@3:2-3:3, `y`@3:4-3:5, Row@3:2 — Quirk E family (FINDINGS #64/#71). Deliverable keeps the
        // body's own physical columns.
        #expect(rows[1].range == r(3, 1, 3, 4))             // physical: unindented body row at col1
        #expect(rows[1].cells[0].range == r(3, 1, 3, 2))    // `x`
        #expect(rows[1].cells[1].range == r(3, 3, 3, 4))    // `y`
    }

    /// A paragraph continuation line that BEGINS WITH A TAB, with multibyte: the deliverable keeps the
    /// continuation's TRUE physical column (after the tab byte); cmark re-indents the continuation to the
    /// paragraph's fixed content column, discarding the tab. Assert the spec-correct flag-OFF value.
    @Test("divergence: a tab-led paragraph continuation keeps its physical column under multibyte")
    func paragraphContinuationLeadingTab() throws {
        // Line 1 `foo`, line 2 `\tbar€`: \t@byte0 (col1), b@byte1 (col2) … €@bytes4-6 (cols5-7).
        let nodes = try nodes("foo\n\tbar\u{20AC}")
        let para = nodes.first { $0.kind == .paragraph }
        let texts = nodes.filter { $0.kind == .text }
        try #require(texts.count == 2 && texts[0].literal == "foo" && texts[1].literal == "bar\u{20AC}",
                     "fixture: two text runs `foo` / `bar€`")
        #expect(para?.range == r(1, 1, 2, 8))
        #expect(texts[0].range == r(1, 1, 1, 4))            // `foo`
        // cmark differs: re-indents the continuation to the top-level content column — `bar€`@2:1-2:7
        // (the tab discarded) — Quirk E (paragraph continuation-line re-indent, FINDINGS #31/#53).
        #expect(texts[1].range == r(2, 2, 2, 8))            // physical: `bar€` after the tab byte (col2)
    }
}

/// A node's kind, its literal text (if any), and its source range — the DFS unit for the non-table
/// arena/tab cases. File-scope struct + helper to satisfy the noncopyable-borrow recursion rules.
private struct EncNode {
    let kind: MarkdownNode.Kind
    let literal: String?
    let range: Range<MarkdownNode.SourcePosition>?
}

private func dfsEncNodes(_ node: borrowing MarkdownNode, into out: inout [EncNode]) {
    out.append(EncNode(kind: node.kind, literal: node.literal(), range: node.sourceRange))
    node.children.forEach { child in dfsEncNodes(child, into: &out) }
}
