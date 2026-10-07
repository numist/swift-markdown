/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Tables whose delimiter row has one column, such as `|-`, `-|`, `|-|` or `:-` (Tables (extension)).
/// The header row needs no pipe when its cell count matches the delimiter row's. A pipe-less line of
/// dashes is a setext heading underline (Setext headings) rather than a delimiter row.
@Suite("Single-column GFM tables")
struct SingleColumnTableTests {

    private struct Block {
        enum Kind { case none, paragraph, heading, table, other }
        var kind: Kind = .none
        var alignments: [MarkdownNode.TableAlignment] = []
        var headerCells: [String] = []
        var bodyRows: [[String]] = []
    }

    /// Extract a `.table` node's header-cell texts, per-column alignments, and body-row cell texts.
    private func tableBlock(from node: borrowing MarkdownNode) -> Block {
        var block = Block()
        block.kind = .table
        node.children.forEach { row in
            guard case .tableRow(let isHeader) = row.kind else { return }
            var cellTexts: [String] = []
            var aligns: [MarkdownNode.TableAlignment] = []
            row.children.forEach { cell in
                guard case .tableCell(let alignment, _, _) = cell.kind else { return }
                aligns.append(alignment)
                var text = ""
                cell.children.forEach { inline in
                    if let lit = inline.literal() { text += lit }
                }
                cellTexts.append(text)
            }
            if isHeader {
                block.headerCells = cellTexts
                block.alignments = aligns
            } else {
                block.bodyRows.append(cellTexts)
            }
        }
        return block
    }

    /// The first `.table` node anywhere in the tree (DFS), or `nil`. Finds tables nested in a block
    /// quote / list as well as top-level ones.
    private func firstTableShape(in node: borrowing MarkdownNode) -> Block? {
        if case .table = node.kind {
            return tableBlock(from: node)
        }
        var result: Block? = nil
        node.children.forEach { child in
            if result == nil {
                result = firstTableShape(in: child)
            }
        }
        return result
    }

    /// The first block of `source`, classified as a paragraph / heading / table (with table shape).
    /// `.none` when the document has no blocks. Parsed with `.tables`.
    private func firstBlock(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) -> Block {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> Block in
            var blocks: [Block] = []
            doc.root.children.forEach { child in
                var block = Block()
                switch child.kind {
                case .paragraph:
                    block.kind = .paragraph
                case .heading:
                    block.kind = .heading
                case .table:
                    block = tableBlock(from: child)
                default:
                    block.kind = .other
                }
                blocks.append(block)
            }
            return blocks.first ?? Block()
        }
    }

    /// The first `.table` anywhere in `source`, or `nil`.
    private func firstTable(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) -> Block? {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> Block? in
            firstTableShape(in: doc.root)
        }
    }

    @Test("a leading-pipe single-column delimiter row forms a table")
    func leadingPipe() throws {
        let block = firstBlock("a\n|-")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.none])
    }

    @Test("a trailing-pipe single-column delimiter row forms a table")
    func trailingPipe() throws {
        let block = firstBlock("a\n-|")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.none])
    }

    @Test("a both-pipes single-column delimiter row forms a table")
    func bothPipes() throws {
        let block = firstBlock("a\n|-|")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.none])
    }

    @Test("a pipe-less colon single-column delimiter row forms a left-aligned table")
    func pipelessColonLeft() throws {
        // `:-` is not a setext heading underline, so it can be a delimiter row without a pipe.
        let block = firstBlock("a\n:-")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.left])
    }

    @Test("a pipe-less centered single-column delimiter row forms a centered table")
    func pipelessColonCenter() throws {
        let block = firstBlock("a\n:-:")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.center])
    }

    @Test("single-column alignment markers set the column alignment")
    func alignmentVariants() {
        #expect(firstBlock("a\n|:-").alignments == [.left])
        #expect(firstBlock("a\n|-:|").alignments == [.right])
        #expect(firstBlock("a\n|:-:|").alignments == [.center])
    }

    @Test("a single-column table carries body rows")
    func bodyRows() throws {
        let block = firstBlock("a\n|-|\nb\nc")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.bodyRows == [["b"], ["c"]])
    }

    @Test("a top-level row with leading whitespace forms a single-column table")
    func leadingWhitespaceDelimiterRow() throws {
        let block = firstBlock("a\n :-")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.left])
    }

    @Test("a single-column table nested in a block quote forms")
    func nestedBlockQuoteSingleColumn() throws {
        let table = try #require(firstTable("> a\n> :-"), "expected a nested single-column table")
        #expect(table.headerCells == ["a"])
        #expect(table.alignments == [.left])
    }

    @Test("a pipe-less dash-only second line stays a setext heading, not a table")
    func pipelessDashIsSetext() {
        #expect(firstBlock("a\n-").kind == .heading)
        #expect(firstBlock("a\n--").kind == .heading)
        #expect(firstBlock("a\n---").kind == .heading)
    }

    @Test("a second line that is not a delimiter row stays a paragraph")
    func nonDelimiterStaysParagraph() {
        #expect(firstBlock("a\nb").kind == .paragraph)
        #expect(firstBlock("a|b\nc|d").kind == .paragraph)
    }

    @Test("a multi-column table forms")
    func multiColumn() throws {
        let block = firstBlock("a|b\n-|-")
        try #require(block.kind == .table, "expected a two-column table, got \(block.kind)")
        #expect(block.headerCells == ["a", "b"])
        #expect(block.alignments == [.none, .none])
    }

    @Test("a delimiter row indented 4+ columns is not a table")
    func indentedDelimiterStaysParagraph() {
        // Like a setext heading underline, a delimiter row may be indented at most 3 columns; a more
        // indented one is paragraph continuation text. A leading tab is 4 columns (Tabs).
        #expect(firstBlock("o\n\t-").kind == .paragraph)       // tab = 4 columns
        #expect(firstBlock("o\n    -").kind == .paragraph)     // 4 spaces
        #expect(firstBlock("o\n    |-").kind == .paragraph)    // 4 spaces + pipe delimiter
        #expect(firstBlock("o\n\t---").kind == .paragraph)     // tab + `---`
        #expect(firstBlock("o\n\t|-").kind == .paragraph)      // tab + pipe delimiter
        #expect(firstBlock("Foo\n    ---").kind == .paragraph) // 4 spaces + `---`
    }

    @Test("a delimiter row indented fewer than 4 columns forms a table")
    func underIndentedDelimiterFormsTable() {
        #expect(firstBlock("a\n   |-").kind == .table)   // 3 spaces
        #expect(firstBlock("a\n  :-:").kind == .table)   // 2 spaces
    }
}
