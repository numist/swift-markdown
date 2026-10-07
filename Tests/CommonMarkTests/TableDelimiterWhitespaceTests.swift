/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A delimiter row cell may be padded with any whitespace character other than a line ending (Characters
/// and lines), including form feed (U+000C) and line tabulation (U+000B) (Tables (extension)).
///
/// Alignment comes from colons at the ends of the cell after trimming only spaces and tabs, so a colon
/// followed by a form feed sets no alignment.
@Suite("Table delimiter-row FF/VT whitespace")
struct TableDelimiterWhitespaceTests {

    private struct Block {
        enum Kind { case none, paragraph, heading, table, other }
        var kind: Kind = .none
        var alignments: [MarkdownNode.TableAlignment] = []
        var headerCells: [String] = []
    }

    /// Extract a `.table` node's header-cell texts and per-column alignments.
    private func tableBlock(from node: borrowing MarkdownNode) -> Block {
        var block = Block()
        block.kind = .table
        node.children.forEach { row in
            guard case .tableRow(let isHeader) = row.kind, isHeader else { return }
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
            block.headerCells = cellTexts
            block.alignments = aligns
        }
        return block
    }

    /// The first `.table` node anywhere in the tree (DFS), or `nil` (finds tables nested in a
    /// block quote / list as well as top-level ones).
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

    /// The first top-level block of `source`, classified as paragraph / heading / table.
    /// Parsed with `.tables`.
    private func firstBlock(_ source: String) -> Block {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Block in
            var blocks: [Block] = []
            doc.root.children.forEach { child in
                var block = Block()
                switch child.kind {
                case .paragraph: block.kind = .paragraph
                case .heading: block.kind = .heading
                case .table: block = tableBlock(from: child)
                default: block.kind = .other
                }
                blocks.append(block)
            }
            return blocks.first ?? Block()
        }
    }

    /// The first `.table` anywhere in `source`, or `nil`.
    private func firstTable(_ source: String) -> Block? {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Block? in
            firstTableShape(in: doc.root)
        }
    }

    private static let ff = "\u{0C}"  // form feed
    private static let vt = "\u{0B}"  // vertical tab
    private static let cr = "\u{0D}"  // carriage return

    // MARK: - Form feed and line tabulation pad a delimiter cell

    @Test("a trailing form-feed in the delimiter cell forms a table")
    func trailingFormFeed() throws {
        let block = firstBlock("d\n-\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a trailing vertical-tab in the delimiter cell forms a table")
    func trailingVerticalTab() throws {
        let block = firstBlock("d\n-\(Self.vt)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a leading-pipe delimiter cell with a trailing form-feed forms a table")
    func leadingPipeTrailingFormFeed() throws {
        let block = firstBlock("d\n|-\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a leading form-feed in the delimiter cell forms a table")
    func leadingFormFeed() throws {
        let block = firstBlock("d\n\(Self.ff)-")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a form-feed delimiter cell forms a table when the delimiter row is indented")
    func indentedDelimiterRowFormFeed() throws {
        let block = firstBlock("d\n -\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a form-feed delimiter cell forms a table nested in a block quote")
    func nestedBlockQuoteFormFeed() throws {
        let table = try #require(firstTable("> d\n> -\(Self.ff)"), "expected a nested table")
        #expect(table.headerCells == ["d"])
        #expect(table.alignments == [.none])
    }

    // MARK: - Alignment

    @Test("a trailing form-feed hides the right-alignment colon")
    func trailingFormFeedHidesRightColon() throws {
        let block = firstBlock("d\n-:\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.alignments == [.none])
    }

    @Test("a leading colon sets left alignment despite a trailing form-feed")
    func leadingColonSetsLeftAlignment() throws {
        let block = firstBlock("d\n:-\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.alignments == [.left])
    }

    // MARK: - Not tables

    @Test("a carriage return after the dash is a line ending, so the line is a setext heading underline")
    func trailingCarriageReturnStaysHeading() {
        #expect(firstBlock("d\n-\(Self.cr)").kind == .heading)
    }

    @Test("an interior form-feed invalidates the delimiter cell")
    func interiorFormFeedStaysParagraph() {
        #expect(firstBlock("d\n-\(Self.ff)-").kind == .paragraph)
    }

    @Test("a column-count mismatch with a form-feed delimiter stays a paragraph")
    func columnMismatchStaysParagraph() {
        #expect(firstBlock("a|b\n-\(Self.ff)").kind == .paragraph)
    }

    @Test("a plain dash second line stays a setext heading")
    func plainDashStaysHeading() {
        #expect(firstBlock("d\n-").kind == .heading)
    }
}
