/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A table is broken at the beginning of another block-level structure (Tables (extension)). Unlike a
/// paragraph, a table can be interrupted by an indented code block, so a line indented four or more
/// columns after the delimiter row closes the table and opens indented code.
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

    // MARK: - Indented four or more columns

    @Test("a tab-indented line after the delimiter row opens indented code")
    func tabIndentBreakout() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\n\tx", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }

    @Test("a four-space-indented line after the delimiter row opens indented code")
    func fourSpaceIndentBreakout() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\n    x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }

    @Test("a five-space-indented line keeps one leftover space in the code content")
    func fiveSpaceIndentBreakout() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\n     x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == [" x\n"])
        }
    }

    @Test("pipes in an indented-code line are literal content, not cells")
    func tabIndentPipesAreLiteral() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\n\tx|y", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(codeBlocks(doc).map(\.literal) == ["x|y\n"])
        }
    }

    @Test("the table keeps its earlier body rows when an indented line closes it")
    func indentBreakoutPreservesEarlierBodyRows() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\nc|d\n\tx", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .indentedCode])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }

    @Test("an indented line closes a table nested in a block quote")
    func indentBreakoutInsideBlockQuote() {
        // The block quote marker and one following space leave four columns of indentation before `x`.
        MarkdownDocument.withParsedDocument("> a|b\n> -|-\n>     x", options: [.tables]) { doc in
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

    // MARK: - Indented zero to three columns

    @Test("an unindented body row stays a table row")
    func zeroIndentBodyRow() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\nx", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).isEmpty)
        }
    }

    @Test("a one-space-indented body row stays a table row")
    func oneSpaceIndentBodyRow() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\n x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).isEmpty)
        }
    }

    @Test("a three-space-indented body row stays a table row")
    func threeSpaceIndentBodyRow() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\n   x", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 1)
            #expect(codeBlocks(doc).isEmpty)
        }
    }

    // MARK: - Other block starts

    @Test("an ATX heading after the delimiter row closes the table")
    func atxHeadingBreakout() {
        MarkdownDocument.withParsedDocument("a|b\n-|-\n# h", options: [.tables]) { doc in
            #expect(topKinds(doc) == [.table, .heading(level: 1)])
            let counts = tableRowCounts(doc)
            #expect(counts.header == 1)
            #expect(counts.body == 0)
            #expect(dfs(doc).last?.literal == "h")
        }
    }
}
