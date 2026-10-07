/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A line holding only a leading pipe (Tables (extension)), optionally with whitespace, has no cells. It
/// is not a body row, so it closes the table and starts a paragraph.
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

    private func analyze(_ source: String) -> Shape {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Shape in
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

    // MARK: - Lone pipe

    @Test("a lone-pipe body row after a single-column header is not a table row")
    func lonePipeBodyRowSingleColumn() throws {
        let s = analyze("f\n|-\n|")
        try #require(s.hasTable, "fixture: expected a table to form from the header + delimiter")
        try #require(s.tableHeaderRows == 1, "fixture: expected exactly one header row")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.table, .paragraph])
        #expect(s.topParagraphTexts == ["|"])
    }

    @Test("a lone-pipe body row after a multi-column header is not a table row")
    func lonePipeBodyRowMultiColumn() throws {
        let s = analyze("a|b\n-|-\n|")
        try #require(s.hasTable, "fixture: expected a two-column table to form")
        try #require(s.tableHeaderRows == 1, "fixture: expected exactly one header row")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.table, .paragraph])
        #expect(s.topParagraphTexts == ["|"])
    }

    // MARK: - Rows with cells

    @Test("a leading+trailing pipe body row is one empty cell, kept as a table row")
    func doublePipeBodyRowStaysARow() throws {
        let s = analyze("f\n|-\n||")
        try #require(s.hasTable, "fixture: expected a table to form")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.table])
        #expect(s.topParagraphTexts.isEmpty)
    }

    @Test("a body row with content is a table row")
    func contentBodyRowStaysARow() throws {
        let s = analyze("a|b\n-|-\nc|d")
        try #require(s.hasTable, "fixture: expected a table to form")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.table])
        #expect(s.topParagraphTexts.isEmpty)
    }
}
