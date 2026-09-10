/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Splitting a GFM table row into cells decides whether a `|` is a cell delimiter or an escaped literal by
/// looking at the byte immediately before it. cmark's row splitter scans each cell with the re2c pattern
/// `table_cell = (escaped_char | [^|\r\n])+` (`extensions/ext_scanners.re`), where `escaped_char` is a
/// backslash followed by any ASCII punctuation (including `\` and `|`). Because re2c takes the LONGEST
/// match, a `|` is pulled into the cell as an escaped pipe whenever the byte directly before it is a
/// backslash — the run of backslashes ahead of that last one is always consumable, so parity does not
/// matter. cmark's `unescape_pipes` (`extensions/table.c`) then drops only the backslash sitting directly
/// before a `|`, and inline parsing resolves the remaining escapes.
///
/// The rewrite previously escaped a pipe only after an ODD number of backslashes (it skipped two bytes per
/// backslash), so `\\|` (two backslashes) wrongly split the pipe off as a delimiter — producing a spurious
/// extra cell (colspan 2 with `.tableSpans`, text `\`) instead of a single cell whose text is `|`. GFM
/// tables are defined by cmark, so this behavior is unconditional (NOT gated on `.cmarkBugCompatibility`).
@Suite("Table backslash-before-pipe cell splitting")
struct TableBackslashPipeCellSplitTests {

    /// `(columns, rows, text)` for each cell of each row of the first table in `source`.
    private func tableCells(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> [[(columns: Int, rows: Int, text: String)]] {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            var rows: [[(columns: Int, rows: Int, text: String)]] = []
            var found = false
            doc.root.children.forEach { block in
                if found || block.kind != .table { return }
                found = true
                block.children.forEach { row in
                    guard case .tableRow = row.kind else { return }
                    var cells: [(columns: Int, rows: Int, text: String)] = []
                    row.children.forEach { cell in
                        guard case .tableCell(_, let columns, let rows) = cell.kind else { return }
                        var text = ""
                        cell.children.forEach { inline in
                            if let lit = inline.literal() { text += lit }
                        }
                        cells.append((columns, rows, text))
                    }
                    rows.append(cells)
                }
            }
            return rows
        }
    }

    /// The finding: body row `\\|` (two backslashes + pipe). The trailing pipe is escaped by the backslash
    /// directly before it, so the row is ONE cell whose content unescapes to `\|` and inline-parses to `|`.
    /// The rewrite used to split the pipe off (colspan 2, text `\`).
    @Test("two backslashes before a pipe keep it in a single cell")
    func twoBackslashesEscapePipe() throws {
        let rows = try tableCells("o\n|-\n\\\\|", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 1, "fixture: body row must be a single cell, got \(rows[1].count)")
        #expect(rows[1][0].columns == 1)
        #expect(rows[1][0].text == "|")
    }

    /// Control that already matched: a single backslash escapes the pipe (`\|` → one cell, text `|`).
    @Test("one backslash before a pipe keeps it in a single cell")
    func oneBackslashEscapesPipe() throws {
        let rows = try tableCells("o\n|-\n\\|", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 1, "fixture: body row must be a single cell, got \(rows[1].count)")
        #expect(rows[1][0].columns == 1)
        #expect(rows[1][0].text == "|")
    }

    /// Control: another even-count case, `\\\\|` (four backslashes + pipe). The pipe is still escaped (byte
    /// before it is a backslash), so it stays one cell. `unescape_pipes` drops only the backslash directly
    /// before the pipe, leaving `\\\|`; inline parsing then resolves `\\` → `\` and `\|` → `|`, so the cell
    /// text is `\|` (backslash then pipe).
    @Test("four backslashes before a pipe keep it in a single cell")
    func fourBackslashesEscapePipe() throws {
        let rows = try tableCells("o\n|-\n\\\\\\\\|", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 1, "fixture: body row must be a single cell, got \(rows[1].count)")
        #expect(rows[1][0].columns == 1)
        #expect(rows[1][0].text == "\\|")
    }

    /// Control: an UNescaped pipe still splits the row into two cells (no backslash before it).
    @Test("an unescaped pipe still splits a body row into two cells")
    func unescapedPipeSplits() throws {
        let rows = try tableCells("x|y\n-|-\na|b", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 2, "fixture: body row must split into two cells, got \(rows[1].count)")
        #expect(rows[1].map(\.columns) == [1, 1])
        #expect(rows[1].map(\.text) == ["a", "b"])
    }
}
