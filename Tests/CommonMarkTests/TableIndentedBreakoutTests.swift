/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// After a GFM table's header + delimiter rows open a table, a following line indented >= 4 columns is
/// NOT a table body row: cmark closes the table and opens an INDENTED CODE BLOCK. In cmark the paragraph
/// has already become a TABLE by the time the indented line is processed, so `open_new_blocks` sees
/// `maybe_lazy == false` (the current block is a table, not a paragraph) and its
/// `indented && !maybe_lazy && !blank` branch opens a code block (blocks.c:1325); `add_child` cannot nest
/// a code block under the table, so the table — with whatever body rows it had — closes and the code block
/// starts at the container's ancestor. The rewrite detects tables at paragraph-finalize and instead
/// absorbed the indented line as a body row; this suite pins the break-out. Spec-aligned `[fix]`, asserted
/// WITHOUT `.cmarkBugCompatibility`.
@Suite("Indented line after a table delimiter row opens indented code")
struct TableIndentedBreakoutTests {

    /// Top-level child kinds of the document, in order.
    private func topKinds(_ doc: borrowing MarkdownDocument) -> [MarkdownNode.Kind] {
        var out: [MarkdownNode.Kind] = []
        doc.root.children.forEach { out.append($0.kind) }
        return out
    }

    /// Header- and body-row counts of the first (and here only) table in the document.
    private func tableRowCounts(_ doc: borrowing MarkdownDocument) -> (header: Int, body: Int) {
        let kinds = dfs(doc).map(\.kind)
        let header = kinds.filter { $0 == .tableRow(isHeader: true) }.count
        let body = kinds.filter { $0 == .tableRow(isHeader: false) }.count
        return (header, body)
    }

    // MARK: - FIX: an indented (>= 4 col) line breaks out of the table into indented code

    @Test("a tab-indented line after the delimiter row opens indented code")
    func tabIndentBreakout() throws {
        // `a|b\n-|-\n\tx`: header `a|b` + delimiter `-|-` open a 2-column table, then a tab-indented `x`.
        // The tab reaches column 4, so `x` is indented code, not a body row.
        try MarkdownDocument.withParsedDocument("a|b\n-|-\n\tx", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }

    @Test("a four-space-indented line after the delimiter row opens indented code")
    func fourSpaceIndentBreakout() throws {
        // `a|b\n-|-\n    x`: four spaces = column 4, so `x` is indented code.
        try MarkdownDocument.withParsedDocument("a|b\n-|-\n    x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }

    @Test("a five-space-indented line keeps one leftover space in the code content")
    func fiveSpaceIndentBreakout() throws {
        // `a|b\n-|-\n     x`: five spaces; four are stripped as the code indent, one survives → ` x`.
        try MarkdownDocument.withParsedDocument("a|b\n-|-\n     x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == [" x\n"])
        }
    }

    @Test("pipes in an indented-code line are literal content, not cells")
    func tabIndentPipesAreLiteral() throws {
        // `a|b\n-|-\n\tx|y`: the tab makes `x|y` indented code, so the pipe is literal code content.
        try MarkdownDocument.withParsedDocument("a|b\n-|-\n\tx|y", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == ["x|y\n"])
        }
    }

    @Test("the table keeps its already-accumulated body rows when the indented line closes it")
    func indentBreakoutPreservesEarlierBodyRows() throws {
        // `a|b\n-|-\nc|d\n\tx`: `c|d` is a valid body row, absorbed before the tab-indented `x` breaks out.
        // The table closes carrying that one body row, then `x` opens indented code.
        try MarkdownDocument.withParsedDocument("a|b\n-|-\nc|d\n\tx", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }

    @Test("the break-out works when the table is nested in a block quote")
    func indentBreakoutInsideBlockQuote() throws {
        // `> a|b\n> -|-\n>     x`: inside a block quote, `> ` consumes the marker + one space, leaving four
        // columns of indent before `x` — indented code, measured relative to the block-quote content column.
        try MarkdownDocument.withParsedDocument("> a|b\n> -|-\n>     x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.blockQuote])
            var quoteChildren: [MarkdownNode.Kind] = []
            doc.root.children.forEach { block in
                block.children.forEach { quoteChildren.append($0.kind) }
            }
            #expect(quoteChildren == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }

    // MARK: - GUARD: a body row indented 0-3 columns stays a body row (unchanged)

    @Test("an unindented body row stays a table row")
    func zeroIndentBodyRow() throws {
        try MarkdownDocument.withParsedDocument("a|b\n-|-\nx", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).isEmpty)
        }
    }

    @Test("a one-space-indented body row stays a table row")
    func oneSpaceIndentBodyRow() throws {
        try MarkdownDocument.withParsedDocument("a|b\n-|-\n x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).isEmpty)
        }
    }

    @Test("a three-space-indented body row stays a table row")
    func threeSpaceIndentBodyRow() throws {
        try MarkdownDocument.withParsedDocument("a|b\n-|-\n   x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).isEmpty)
        }
    }

    // MARK: - GUARD: an already-working break-out (a block start) is unaffected

    @Test("an ATX heading after the delimiter row still closes the table")
    func atxHeadingBreakout() throws {
        // `a|b\n-|-\n# h`: `# h` is a block start (`!indented`), which already breaks out of the table.
        try MarkdownDocument.withParsedDocument("a|b\n-|-\n# h", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .heading(level: 1)])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(dfs(doc).last?.literal == "h")
        }
    }
}
