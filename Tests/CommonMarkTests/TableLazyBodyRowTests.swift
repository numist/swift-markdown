/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Laziness applies only to paragraph continuation text (Block quotes, List items). Once a table opens in a
/// container, a following line without the container's prefix is not a lazy continuation line: it closes
/// the table and the container and starts a new paragraph.
@Suite("Table followed by a line without its container's prefix")
struct TableLazyBodyRowTests {

    private struct Shape {
        /// Kinds of the document root's direct children, in order.
        var topKinds: [MarkdownNode.Kind] = []
        /// The first table found anywhere in the tree, if any.
        var hasTable = false
        /// The first table is a descendant of a top-level block quote.
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
        var inBlockQuote = insideBlockQuote
        if case .blockQuote = node.kind { inBlockQuote = true }
        node.children.forEach { recordFirstTable($0, insideBlockQuote: inBlockQuote, shape: &shape) }
    }

    private func analyze(_ source: String) -> Shape {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Shape in
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

    // MARK: - Unprefixed lines close the table and its container

    @Test("an unprefixed row closes the table and block quote and starts a paragraph")
    func lazyBodyRowBreaksOut() throws {
        let s = analyze(">a|b\n>-|-\nc|d")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        try #require(s.tableHeaderRows == 1, "fixture: expected exactly one header row")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        #expect(s.topParagraphTexts == ["c|d"])
    }

    @Test("two unprefixed lines after the delimiter row form one paragraph")
    func twoLazyLinesFormOneParagraph() throws {
        let s = analyze(">a|b\n>-|-\nc|d\ne|f")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        try #require(s.topParagraphTexts.count == 1, "expected exactly one top-level paragraph")
        #expect(s.topParagraphHasSoftBreak == [true])
    }

    @Test("unprefixed text without pipes after the delimiter row starts a paragraph")
    func lazyNonTableTextBreaksOut() throws {
        let s = analyze(">a|b\n>-|-\nxy")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 0)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        #expect(s.topParagraphTexts == ["xy"])
    }

    @Test("a row not indented to a list item's content closes the table and list")
    func lazyBodyRowBreaksOutOfListItem() throws {
        let s = analyze("- a|b\n  -|-\nc|d")
        try #require(s.hasTable, "fixture: expected a table to have formed in the list item")
        #expect(s.tableBodyRows == 0)
        try #require(s.topKinds.count == 2, "expected the list plus a paragraph, got \(s.topKinds)")
        #expect(s.topParagraphTexts == ["c|d"])
    }

    // MARK: - Prefixed body rows

    @Test("a prefixed body row stays in the table; a following unprefixed line starts a paragraph")
    func matchedBodyThenLazyBreaksOut() throws {
        let s = analyze(">a|b\n>-|-\n>c|d\ne|f")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.blockQuote, .paragraph])
        #expect(s.topParagraphTexts == ["e|f"])
    }

    @Test("a prefixed body row is a table body row inside the block quote")
    func prefixedBodyRowStaysInTable() throws {
        let s = analyze(">a|b\n>-|-\n>c|d")
        try #require(s.hasTable && s.blockQuoteContainsTable, "fixture: expected a table inside the block quote")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.blockQuote])
        #expect(s.topParagraphTexts.isEmpty)
    }

    @Test("a table outside any container gets its body row")
    func plainTableGetsBodyRow() throws {
        let s = analyze("a|b\n-|-\nc|d")
        try #require(s.hasTable && !s.blockQuoteContainsTable, "fixture: expected a top-level table")
        #expect(s.tableBodyRows == 1)
        #expect(s.topKinds == [.table])
        #expect(s.topParagraphTexts.isEmpty)
    }
}
