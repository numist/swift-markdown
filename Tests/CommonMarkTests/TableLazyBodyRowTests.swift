/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Once a GFM table has opened inside a container (a header line + a delimiter line that BOTH carry the
/// container's prefix), a subsequent LAZY continuation line (one WITHOUT the container's `>` / list-indent
/// prefix) cannot be a table body row. cmark opens the table while processing the delimiter line
/// (`try_opening_table_block`), so by the time the lazy line arrives the open block is a TABLE, not a
/// paragraph; the lazy-paragraph branch in `add_text_to_container` therefore does not fire, and the table
/// and its enclosing container close so the line starts a fresh paragraph at the container's ancestor
/// (document) level. The rewrite detects tables at finalize, so it used to absorb the lazy line into the
/// block-quote paragraph and turn the accumulated content into a table body row. This suite pins cmark's
/// break-out. Spec-aligned `[fix]`, asserted WITHOUT `.cmarkBugCompatibility`.
@Suite("Table lazy-continuation body row")
struct TableLazyBodyRowTests {

    private struct Shape {
        /// Kinds of the document root's direct children, in order.
        var topKinds: [MarkdownNode.Kind] = []
        /// The first table found anywhere in the tree, if any.
        var hasTable = false
        /// A table was found as a descendant of a top-level block quote.
        var blockQuoteContainsTable = false
        /// Header / body row counts of the first table found.
        var tableHeaderRows = 0
        var tableBodyRows = 0
        /// Concatenated literal text of each top-level `.paragraph`, in order.
        var topParagraphTexts: [String] = []
        /// Whether each top-level `.paragraph` contains a `.softBreak` descendant (lines joined in one paragraph).
        var topParagraphHasSoftBreak: [Bool] = []
    }

    /// Concatenate every `literal()` under `node` (depth-first) and note whether a `.softBreak` appears.
    private func gatherText(_ node: borrowing MarkdownNode, into text: inout String, sawSoftBreak: inout Bool) {
        if case .softBreak = node.kind { sawSoftBreak = true }
        if let l = node.literal() { text += l }
        node.children.forEach { gatherText($0, into: &text, sawSoftBreak: &sawSoftBreak) }
    }

    /// Count header / body rows and note the block-quote-containment of the first table found under `node`.
    private func recordFirstTable(_ node: borrowing MarkdownNode, insideBlockQuote: Bool, shape: inout Shape) {
        if !shape.hasTable, case .table = node.kind {
            shape.hasTable = true
            shape.blockQuoteContainsTable = insideBlockQuote
            node.children.forEach { row in
                if case .tableRow(let isHeader) = row.kind {
                    if isHeader { shape.tableHeaderRows += 1 } else { shape.tableBodyRows += 1 }
                }
            }
            return
        }
        var nowInBQ = insideBlockQuote
        if case .blockQuote = node.kind { nowInBQ = true }
        node.children.forEach { recordFirstTable($0, insideBlockQuote: nowInBQ, shape: &shape) }
    }

    private func analyze(_ source: String) throws -> Shape {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Shape in
            var shape = Shape()
            doc.root.children.forEach { block in
                shape.topKinds.append(block.kind)
                if case .paragraph = block.kind {
                    var text = ""
                    var sawSoftBreak = false
                    gatherText(block, into: &text, sawSoftBreak: &sawSoftBreak)
                    shape.topParagraphTexts.append(text)
                    shape.topParagraphHasSoftBreak.append(sawSoftBreak)
                }
            }
            recordFirstTable(doc.root, insideBlockQuote: false, shape: &shape)
            return shape
        }
    }

    // MARK: - FIX: a lazy body row breaks out of the table and its container

    @Test("a lazy body row closes the table + block quote and starts a document paragraph")
    func lazyBodyRowBreaksOut() throws {
        let s = try analyze(">a|b\n>-|-\nc|d")
        // Fixture sanity: a table did form inside the block quote.
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        try #require(s.tableHeaderRows == 1, "fixture: expected exactly one header row")
        // The table is header-only; the lazy `c|d` became a top-level paragraph, NOT a body row.
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        #expect(s.topParagraphTexts == ["c|d"])
    }

    @Test("two lazy lines after the delimiter form ONE document paragraph")
    func twoLazyLinesFormOneParagraph() throws {
        let s = try analyze(">a|b\n>-|-\nc|d\ne|f")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        // Both lazy lines join into a single top-level paragraph (a soft break between them).
        try #require(s.topParagraphTexts.count == 1, "expected exactly one top-level paragraph")
        #expect(s.topParagraphHasSoftBreak == [true])
    }

    @Test("lazy non-table text after the delimiter breaks out to a document paragraph")
    func lazyNonTableTextBreaksOut() throws {
        let s = try analyze(">a|b\n>-|-\nxy")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        #expect(s.topParagraphTexts == ["xy"])
    }

    @Test("a lazy body row breaks out of a LIST-ITEM container too (signal is container-agnostic)")
    func lazyBodyRowBreaksOutOfListItem() throws {
        // The break-out signal is `currentLineIsLazyContinuation` (some open container's prefix failed),
        // not block-quote-specific: `c|d` is not indented to the item's content column, so it is a lazy
        // continuation and breaks out. cmark: List › Item › Table(header only) + document Paragraph "c|d".
        let s = try analyze("- a|b\n  -|-\nc|d")
        try #require(s.hasTable, "fixture: expected a table to have formed in the list item")
        #expect(s.tableBodyRows == 0)
        // The list is the first top-level block; the broken-out paragraph is a second top-level block.
        try #require(s.topKinds.count == 2, "expected the list plus a broken-out paragraph, got \(s.topKinds)")
        #expect(s.topParagraphTexts == ["c|d"])
    }

    // MARK: - Boundary: a matched body row THEN a lazy line

    @Test("a matched body row keeps its table row; a following lazy line still breaks out")
    func matchedBodyThenLazyBreaksOut() throws {
        // `>c|d` is a prefix-matched body row (stays in the table); the later un-prefixed `e|f` is a lazy
        // continuation that breaks out. cmark: BlockQuote › Table(header + body "c","d") + document
        // Paragraph "e|f".
        let s = try analyze(">a|b\n>-|-\n>c|d\ne|f")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        #expect(s.topParagraphTexts == ["e|f"])
    }

    // MARK: - LEAVE: a prefixed body row and a plain (no-container) table still get a body row

    @Test("a PREFIXED body row still becomes a table body row inside the block quote")
    func prefixedBodyRowStaysInTable() throws {
        let s = try analyze(">a|b\n>-|-\n>c|d")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 1)
        // No break-out: the block quote is the sole top-level block, no stray paragraph.
        #expect(s.topKinds == [.blockQuote])
        #expect(s.topParagraphTexts.isEmpty)
    }

    @Test("a plain (no-container) table still gets its body row")
    func plainTableStillGetsBodyRow() throws {
        let s = try analyze("a|b\n-|-\nc|d")
        try #require(s.hasTable && !s.blockQuoteContainsTable, "fixture: expected a top-level table")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.table])
        #expect(s.topParagraphTexts.isEmpty)
    }
}
