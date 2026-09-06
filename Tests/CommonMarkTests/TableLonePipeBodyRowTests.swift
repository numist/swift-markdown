/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A body-row line that scans to ZERO table columns (a lone `|`, optionally padded with
/// delimiter-marker whitespace) is not a table row. cmark's `matches` calls `row_from_string`,
/// which creates cells only inside its scan loop; the consumed leading pipe never enters the loop,
/// so `n_columns == 0` and the row does not match. The open table therefore closes and the line is
/// re-dispatched as a fresh block (a paragraph). The rewrite detects tables at paragraph-finalize
/// and autocompleted the accumulated lone-pipe line into a spurious one-empty-cell body row; this
/// suite pins cmark's table-termination. Spec-aligned `[fix]`, asserted WITHOUT
/// `.cmarkBugCompatibility`.
@Suite("Lone-pipe table body row terminates the table")
struct TableLonePipeBodyRowTests {

    private struct Shape {
        /// Kinds of the document root's direct children, in order.
        var topKinds: [MarkdownNode.Kind] = []
        /// Whether the first table found has a header row, and its body-row count.
        var hasTable = false
        var tableHeaderRows = 0
        var tableBodyRows = 0
        /// Concatenated literal text of each top-level `.paragraph`, in order.
        var topParagraphTexts: [String] = []
    }

    /// Concatenate every `literal()` under `node` (depth-first).
    private func gatherText(_ node: borrowing MarkdownNode, into text: inout String) {
        if let l = node.literal() { text += l }
        node.children.forEach { gatherText($0, into: &text) }
    }

    /// Count header / body rows of the first table found under `node`.
    private func recordFirstTable(_ node: borrowing MarkdownNode, shape: inout Shape) {
        if !shape.hasTable, case .table = node.kind {
            shape.hasTable = true
            node.children.forEach { row in
                if case .tableRow(let isHeader) = row.kind {
                    if isHeader { shape.tableHeaderRows += 1 } else { shape.tableBodyRows += 1 }
                }
            }
            return
        }
        node.children.forEach { recordFirstTable($0, shape: &shape) }
    }

    private func analyze(_ source: String) throws -> Shape {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Shape in
            var shape = Shape()
            doc.root.children.forEach { block in
                shape.topKinds.append(block.kind)
                if case .paragraph = block.kind {
                    var text = ""
                    gatherText(block, into: &text)
                    shape.topParagraphTexts.append(text)
                }
            }
            recordFirstTable(doc.root, shape: &shape)
            return shape
        }
    }

    // MARK: - FIX: a zero-column body row closes the table and starts a paragraph

    @Test("a lone-pipe body row after a single-column header is not a table row")
    func lonePipeBodyRowSingleColumn() throws {
        // `f\n|-\n|` : header `f` (1 column) + delimiter `|-`, then a lone `|` body line. cmark:
        // Table(header "f", empty body) + Paragraph "|".
        let s = try analyze("f\n|-\n|")
        try #require(s.hasTable, "fixture: expected a table to form from the header + delimiter")
        try #require(s.tableHeaderRows == 1, "fixture: expected exactly one header row")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.table, .paragraph])
        #expect(s.topParagraphTexts == ["|"])
    }

    @Test("a lone-pipe body row after a multi-column header is not a table row")
    func lonePipeBodyRowMultiColumn() throws {
        // `a|b\n-|-\n|` : header `a|b` (2 columns) + delimiter `-|-`, then a lone `|` body line. cmark:
        // Table(header "a","b", empty body) + Paragraph "|". The class is column-count-agnostic.
        let s = try analyze("a|b\n-|-\n|")
        try #require(s.hasTable, "fixture: expected a two-column table to form")
        try #require(s.tableHeaderRows == 1, "fixture: expected exactly one header row")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.table, .paragraph])
        #expect(s.topParagraphTexts == ["|"])
    }

    // MARK: - LEAVE guards: rows that DO scan to a cell stay in the table

    @Test("a leading+trailing pipe body row is one empty cell, kept as a table row")
    func doublePipeBodyRowStaysARow() throws {
        // `||` scans to ONE (empty) cell, so it continues the table as a body row - no break-out.
        let s = try analyze("f\n|-\n||")
        try #require(s.hasTable, "fixture: expected a table to form")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.table])
        #expect(s.topParagraphTexts.isEmpty)
    }

    @Test("an ordinary content body row is unaffected")
    func contentBodyRowStaysARow() throws {
        let s = try analyze("a|b\n-|-\nc|d")
        try #require(s.hasTable, "fixture: expected a table to form")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.table])
        #expect(s.topParagraphTexts.isEmpty)
    }
}
