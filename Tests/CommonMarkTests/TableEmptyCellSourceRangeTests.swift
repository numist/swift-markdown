/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source-range coverage for empty / whitespace-only GFM table cells, plus the rightmost content cell
/// whose trailing whitespace runs to the line end — cases where the rewrite must reproduce cmark-gfm's
/// offsets (a differential-qualification `[fix]`, tracked unconditionally — see FINDINGS #11).
///
/// cmark computes a cell's end offset over the UNTRIMMED between-pipes extent (`row_from_string` in
/// swift-cmark's `extensions/table.c`): a content cell ends just past its last non-pipe byte, but an
/// empty/whitespace-only cell's end offset points AT the closing pipe (inclusive), so its half-open end
/// lands one byte further — past the closing pipe. When the rightmost cell has NO closing pipe,
/// `scan_table_cell` matches through its trailing whitespace to the line end, so its end reaches the
/// row's untrimmed end. A zero-width `||` cell is additionally flagged `colspan: 0`, and that flag
/// applies to the first column too (cmark's `n_columns > 0` guard is always satisfied). A table row
/// spans its full source line including trailing whitespace.
///
/// Columns are 1-based; `sourceRange.upperBound.column` is half-open (one past the last byte), matching
/// the `debugDescription` surface the differential fuzzer compares.
@Suite("Table empty-cell source ranges")
struct TableEmptyCellSourceRangeTests {

    private struct Cell {
        let colspan: Int
        let startColumn: Int
        let endColumn: Int
        let text: String
        /// The first inline child's source range (line, column) for start and end, or `nil` if the cell
        /// has no positioned inline. Stamped by the inline pass, a separate path from the cell node itself.
        let textStart: (line: Int, column: Int)?
        let textEnd: (line: Int, column: Int)?
    }

    private struct Row {
        let startColumn: Int
        let endColumn: Int
        let line: Int
        let cells: [Cell]
    }

    /// Rows (with per-cell columns, colspan, and text) of the first table in `source`, parsed with
    /// spans + source positions. `nil` cell entries mark cells with no source range (autocompleted).
    private func tableRows(_ source: String) throws -> [Row] {
        try tableRows(source, options: [.tables, .tableSpans, .sourcePosition])
    }

    private func tableRows(_ source: String, options: MarkdownDocument.ParseOptions) throws -> [Row] {
        try MarkdownDocument.withParsedDocument(
            source, options: options
        ) { doc -> [Row] in
            var rows: [Row] = []
            var found = false
            doc.root.children.forEach { block in
                if found || block.kind != .table { return }
                found = true
                block.children.forEach { row in
                    guard case .tableRow = row.kind, let rowRange = row.sourceRange else { return }
                    var cells: [Cell] = []
                    row.children.forEach { cell in
                        guard case .tableCell(_, let columns, _) = cell.kind,
                              let range = cell.sourceRange else { return }
                        var text = ""
                        var textStart: (line: Int, column: Int)? = nil
                        var textEnd: (line: Int, column: Int)? = nil
                        cell.children.forEach { inline in
                            if let lit = inline.literal() { text += lit }
                            if textStart == nil, let r = inline.sourceRange {
                                textStart = (r.lowerBound.line, r.lowerBound.column)
                                textEnd = (r.upperBound.line, r.upperBound.column)
                            }
                        }
                        cells.append(Cell(
                            colspan: columns,
                            startColumn: range.lowerBound.column,
                            endColumn: range.upperBound.column,
                            text: text,
                            textStart: textStart,
                            textEnd: textEnd
                        ))
                    }
                    rows.append(Row(
                        startColumn: rowRange.lowerBound.column,
                        endColumn: rowRange.upperBound.column,
                        line: rowRange.lowerBound.line,
                        cells: cells
                    ))
                }
            }
            return rows
        }
    }

    /// A body row with LEADING whitespace re-bases its cell columns to the table's content column under
    /// `.cmarkBugCompatibility` (the differential-fuzzer surface): cmark measures cell offsets from the
    /// row's first non-space, then adds the table start column (`row_from_string(input + first_nonspace,
    /// …)` + `parent->start_column + cell->start_offset` in `extensions/table.c`), so the leading
    /// whitespace is invisible. Before the fix these rows lost ALL cell/row source positions.
    @Test("cmark-compat: a leading-whitespace row's cell columns are re-based (leading whitespace invisible)")
    func leadingWhitespaceReBasedCells() throws {
        let opts: MarkdownDocument.ParseOptions = [.tables, .tableSpans, .sourcePosition, .cmarkBugCompatibility]

        // Body-row leading space: `x` is physically at col 2 but re-bases to col 1.
        let body = try tableRows("a|b\n-|-\n x|y", options: opts)
        let bodyRow = try #require(body.last, "expected a body row")
        try #require(bodyRow.cells.count == 2, "fixture: expected two body cells, got \(bodyRow.cells.count)")
        try #require(bodyRow.cells.allSatisfy { $0.startColumn > 0 }, "fixture: leading-space cells must be positioned, not dropped")
        #expect((bodyRow.cells[0].startColumn, bodyRow.cells[0].endColumn, bodyRow.cells[0].text) == (1, 2, "x"))
        #expect((bodyRow.cells[1].startColumn, bodyRow.cells[1].endColumn, bodyRow.cells[1].text) == (3, 4, "y"))
        // Leading whitespace is invisible: the re-based columns equal an unindented row's.
        let plain = try tableRows("a|b\n-|-\nx|y", options: opts)
        let plainRow = try #require(plain.last, "expected a body row")
        #expect(bodyRow.cells.map { [$0.startColumn, $0.endColumn] } == plainRow.cells.map { [$0.startColumn, $0.endColumn] })

        // A leading-whitespace HEADER sets the table start column that every row re-bases to (col 2 here),
        // shifting even the unindented body row's cells right onto it.
        let hdr = try tableRows(" a|b\n-|-\nx|y", options: opts)
        try #require(hdr.count == 2, "fixture: expected a header row and a body row")
        try #require(hdr[0].cells.count == 2 && hdr[1].cells.count == 2, "fixture: two cells per row")
        #expect((hdr[0].cells[0].startColumn, hdr[0].cells[0].endColumn, hdr[0].cells[0].text) == (2, 3, "a"))
        #expect((hdr[0].cells[1].startColumn, hdr[0].cells[1].endColumn, hdr[0].cells[1].text) == (4, 5, "b"))
        #expect((hdr[1].cells[0].startColumn, hdr[1].cells[0].endColumn, hdr[1].cells[0].text) == (2, 3, "x"))
        #expect((hdr[1].cells[1].startColumn, hdr[1].cells[1].endColumn, hdr[1].cells[1].text) == (4, 5, "y"))
    }

    /// The deliverable (without `.cmarkBugCompatibility`) is spec-correct: a leading-whitespace row's
    /// cells keep their TRUE physical columns (the leading whitespace is visible) — the cmark-compat
    /// re-base above is quarantined to the differential. The fix's other half applies here too: the
    /// cells are positioned, not dropped.
    @Test("spec: a leading-whitespace row's cells keep their physical columns and are positioned")
    func leadingWhitespacePhysicalCellsSpecCorrect() throws {
        // Default helper: no `.cmarkBugCompatibility`.
        let body = try tableRows("a|b\n-|-\n x|y")
        let bodyRow = try #require(body.last, "expected a body row")
        try #require(bodyRow.cells.count == 2, "fixture: expected two body cells, got \(bodyRow.cells.count)")
        try #require(bodyRow.cells.allSatisfy { $0.startColumn > 0 }, "fixture: cells must be positioned, not dropped")
        // Physical columns: `x` at col 2, `y` at col 4 (leading space visible).
        #expect((bodyRow.cells[0].startColumn, bodyRow.cells[0].endColumn, bodyRow.cells[0].text) == (2, 3, "x"))
        #expect((bodyRow.cells[1].startColumn, bodyRow.cells[1].endColumn, bodyRow.cells[1].text) == (4, 5, "y"))
    }

    /// A whitespace-only cell's end column spans past its closing pipe (untrimmed extent), while the
    /// surrounding content cells keep their trimmed-content ends.
    @Test("a whitespace-only cell ends one column past its closing pipe")
    func whitespaceCellEndColumn() throws {
        // `|x| |y`: x at col 2, empty cell is the space at col 4 with its closing pipe at col 5.
        let rows = try tableRows("a|b|c\n-|-|-\n|x| |y")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 3, "expected three body cells, got \(body.cells.count)")
        // Content cell `x`: ends at its closing pipe (col 3), unchanged.
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (2, 3))
        #expect(body.cells[0].text == "x")
        // Whitespace-only middle cell: starts at the space (col 4), ends PAST the closing pipe (col 6).
        #expect(body.cells[1].text == "")
        #expect(body.cells[1].colspan == 1)
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (4, 6))
        // Trailing content cell `y`.
        #expect((body.cells[2].startColumn, body.cells[2].endColumn) == (6, 7))
        #expect(body.cells[2].text == "y")
    }

    /// A multi-space empty cell widens accordingly: `|   |c` empty cell spans col 2 through col 6.
    @Test("a multi-space empty cell spans its whole untrimmed width plus the closing pipe")
    func multiSpaceEmptyCellEndColumn() throws {
        let rows = try tableRows("a|b\n-|-\n|   |c")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].text == "")
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (2, 6))
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (6, 7))
    }

    /// A zero-width `||` cell in the FIRST column is a colspan filler (colspan 0), matching cmark. Its
    /// end column is one past the (zero-width) closing pipe.
    @Test("a zero-width first cell is a colspan filler (colspan 0)")
    func zeroWidthFirstCellColspan() throws {
        // Body row `||c`: leading empty cell between the two pipes.
        let bodyRows = try tableRows("a|b\n-|-\n||c")
        let body = try #require(bodyRows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].colspan == 0)
        #expect(body.cells[0].text == "")
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (2, 3))

        // The same holds for a zero-width cell in the HEADER row.
        let headerRows = try tableRows("||b\n-|-\nx|y")
        let header = try #require(headerRows.first, "expected a header row")
        try #require(header.cells.count == 2, "expected two header cells, got \(header.cells.count)")
        #expect(header.cells[0].colspan == 0)
        #expect((header.cells[0].startColumn, header.cells[0].endColumn) == (2, 3))
    }

    /// A table row's end column includes trailing whitespace on its source line, even when that line is
    /// the last line of the paragraph (whose content chunk is trailing-trimmed before table parsing).
    @Test("the last row's end column includes trailing whitespace")
    func lastRowEndIncludesTrailingWhitespace() throws {
        // Body row `|c| ` (trailing space): the real cell `c`, then an autocompleted (positionless) cell.
        let rows = try tableRows("a|b\n-|-\n|c| ")
        let body = try #require(rows.last, "expected a body row")
        #expect(body.line == 3)
        // `|c| ` occupies columns 1–4; the row spans through the trailing space, ending at col 5.
        #expect(body.startColumn == 1)
        #expect(body.endColumn == 5)
    }

    /// A content cell surrounded by whitespace keeps its trimmed-content END (does NOT gain the +1 the
    /// empty-cell rule adds) — the boundary case that pins the fix to genuinely empty cells.
    @Test("a content cell with surrounding whitespace keeps its trimmed end column")
    func contentCellWithSpacesUnchanged() throws {
        // `| x |c`: the ` x ` cell spans col 2 (leading space) through col 5 (its closing pipe), and its
        // inner Text `x` sits at cols 3–4.
        let rows = try tableRows("a|b\n-|-\n| x |c")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].text == "x")
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (2, 5))
    }

    /// The rightmost cell on a row with NO closing pipe extends through its trailing whitespace to the
    /// row's untrimmed line end: cmark's `scan_table_cell` matches everything up to the line end when no
    /// pipe stops it, so the cell's end offset spans the trailing whitespace `splitCells` trims off its
    /// content. cmark counts a trailing tab as a single byte-column (no tab expansion).
    @Test("a rightmost body cell with trailing whitespace and no closing pipe extends to the line end")
    func rightmostBodyCellTrailingWhitespaceExtends() throws {
        // `x|y ` (one trailing space, no closing pipe): Text `y` at cols 3–4, but the cell reaches the
        // row's untrimmed end at col 5.
        let rows = try tableRows("a|b\n-|-\nx|y ")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[1].text == "y")
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (3, 5))
        // The cell reaches exactly the row's own untrimmed end.
        #expect(body.endColumn == 5)
    }

    /// The same untrimmed-extent rule applies to the HEADER row's rightmost cell.
    @Test("a rightmost header cell with trailing whitespace and no closing pipe extends to the line end")
    func rightmostHeaderCellTrailingWhitespaceExtends() throws {
        // Header `a|b  ` (two trailing spaces): Text `b` at cols 3–4, cell reaches the line end at col 6.
        let rows = try tableRows("a|b  \n-|-\nx|y")
        let header = try #require(rows.first, "expected a header row")
        try #require(header.cells.count == 2, "expected two header cells, got \(header.cells.count)")
        #expect(header.cells[1].text == "b")
        #expect((header.cells[1].startColumn, header.cells[1].endColumn) == (3, 6))
        #expect(header.endColumn == 6)
    }

    /// A closing pipe caps the rightmost cell AT the pipe (the pipe stops cmark's cell scan), so its end
    /// stays below the row end even when the cell holds trailing whitespace before the pipe. This is the
    /// discriminator the fix keys on: extend only when there is no closing pipe.
    @Test("a rightmost cell capped by a closing pipe keeps its at-pipe end, below the row end")
    func rightmostCellClosingPipeNotExtended() throws {
        // `x|y |`: the cell `y ` ends at the pipe (col 5) while the row spans through it to col 6.
        let rows = try tableRows("a|b\n-|-\nx|y |")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[1].text == "y")
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (3, 5))
        #expect(body.endColumn == 6)
    }

    /// A rightmost cell with no trailing whitespace is not over-extended: its end sits flush with its
    /// content, coinciding with the row end.
    @Test("a rightmost cell with no trailing whitespace is not over-extended")
    func rightmostCellNoTrailingWhitespaceUnchanged() throws {
        // `x|y` (no trailing whitespace, no closing pipe): cell end sits flush with the content at col 4.
        let rows = try tableRows("a|b\n-|-\nx|y")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (3, 4))
        #expect(body.endColumn == 4)
    }
}
