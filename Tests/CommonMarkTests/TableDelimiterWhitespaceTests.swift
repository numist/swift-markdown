/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// GFM table DELIMITER-ROW whitespace: cmark treats form-feed (U+000C) and vertical-tab (U+000B) as
/// cell whitespace when validating a delimiter marker. cmark's `scan_table_start` validates the
/// marker as `table_marker = spacechar*[:]?[-]+[:]?spacechar*` with `spacechar = [ \t\v\f]`, so a cell
/// with leading/trailing FF/VT around `:?-+:?` is still a valid delimiter cell and a table forms. The
/// rewrite treated FF/VT as ordinary content, so the cell failed validation and the paragraph never
/// became a table.
///
/// Alignment is a SEPARATE notion: cmark reads the colon flags from the cell buffer trimmed by
/// `cmark_strbuf_trim`, whose `cmark_isspace` set is `[ \t\n\r]` and EXCLUDES VT/FF. So a colon hidden
/// behind a trailing FF/VT is not seen — the marker is still structurally valid, but the column reports
/// no alignment. These tests pin both notions.
///
/// FF/VT are cell whitespace ONLY inside a delimiter marker. CR (U+000D) is a line terminator, not cell
/// whitespace; an interior FF/VT still invalidates a cell; and a column-count mismatch is still not a
/// table. This is a spec-aligned `[fix]` (FF/VT are CommonMark whitespace, §2.1), asserted WITHOUT
/// `.cmarkBugCompatibility`.
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
    /// Parsed with `.tables` but WITHOUT `.cmarkBugCompatibility`.
    private func firstBlock(_ source: String) throws -> Block {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Block in
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
    private func firstTable(_ source: String) throws -> Block? {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> Block? in
            firstTableShape(in: doc.root)
        }
    }

    private static let ff = "\u{0C}"  // form feed
    private static let vt = "\u{0B}"  // vertical tab
    private static let cr = "\u{0D}"  // carriage return

    // MARK: - FIX: FF/VT as delimiter-cell whitespace forms a table

    @Test("a trailing form-feed in the delimiter cell still forms a table")
    func trailingFormFeed() throws {
        // `d\n-\f` — the FF pads the marker (cmark's spacechar), so `-\f` is a valid `-` cell.
        let block = try firstBlock("d\n-\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a trailing vertical-tab in the delimiter cell still forms a table")
    func trailingVerticalTab() throws {
        let block = try firstBlock("d\n-\(Self.vt)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a leading-pipe delimiter cell with a trailing form-feed still forms a table")
    func leadingPipeTrailingFormFeed() throws {
        let block = try firstBlock("d\n|-\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a leading form-feed in the delimiter cell still forms a table")
    func leadingFormFeed() throws {
        let block = try firstBlock("d\n\(Self.ff)-")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a form-feed delimiter cell forms a table on the segment (leading-whitespace) path")
    func segmentPathFormFeed() throws {
        // A leading space on the delimiter line makes the paragraph non-contiguous, so it reaches table
        // detection as a segment list — exercising the segment-gate, not the contiguous fast-path gate.
        let block = try firstBlock("d\n -\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.headerCells == ["d"])
        #expect(block.alignments == [.none])
    }

    @Test("a form-feed delimiter cell forms a table nested in a block quote (segment path)")
    func nestedBlockQuoteFormFeed() throws {
        // Nested content is a materialized segment list; the same gate must admit the FF-padded marker.
        let table = try #require(try firstTable("> d\n> -\(Self.ff)"), "expected a nested table")
        #expect(table.headerCells == ["d"])
        #expect(table.alignments == [.none])
    }

    // MARK: - Alignment reads the space/tab-trimmed buffer (VT/FF do NOT trim for colon detection)

    @Test("a trailing form-feed hides the right-alignment colon (matches cmark's buffer inspection)")
    func trailingFormFeedHidesRightColon() throws {
        // `d\n-:\f`: the marker `-:\f` is structurally valid (right-aligned shape) and forms a table,
        // but cmark reads alignment from the `cmark_strbuf_trim`'d buffer, which keeps the trailing FF,
        // so the colon at buf[size-2] is not the last byte — alignment is NONE, not right.
        let block = try firstBlock("d\n-:\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.alignments == [.none])
    }

    @Test("a leading colon before the dash is still seen as left alignment despite a trailing form-feed")
    func leadingColonStillLeft() throws {
        // `d\n:-\f`: the leading colon is at buf[0], unaffected by the trailing FF, so it is left-aligned.
        let block = try firstBlock("d\n:-\(Self.ff)")
        try #require(block.kind == .table, "expected a table, got \(block.kind)")
        #expect(block.alignments == [.left])
    }

    // MARK: - LEAVE: guards that must NOT become tables

    @Test("a carriage return after the dash is a line terminator, not cell whitespace (stays a heading)")
    func trailingCarriageReturnStaysHeading() throws {
        // CR ends the line, leaving a bare `-` setext underline: a heading, never a table.
        #expect(try firstBlock("d\n-\(Self.cr)").kind == .heading)
    }

    @Test("an interior form-feed invalidates the delimiter cell (stays a paragraph)")
    func interiorFormFeedStaysParagraph() throws {
        // `d\n-\f-`: FF between dashes is interior, not trimmed; the cell is not `:?-+:?`, so no table.
        #expect(try firstBlock("d\n-\(Self.ff)-").kind == .paragraph)
    }

    @Test("a column-count mismatch with a form-feed delimiter stays a paragraph")
    func columnMismatchStaysParagraph() throws {
        // `a|b\n-\f`: header has 2 columns, the FF-padded delimiter has 1 — mismatch, so not a table.
        #expect(try firstBlock("a|b\n-\(Self.ff)").kind == .paragraph)
    }

    @Test("a plain dash second line stays a setext heading")
    func plainDashStaysHeading() throws {
        // No FF/VT: `-` is a setext underline resolved before table detection.
        #expect(try firstBlock("d\n-").kind == .heading)
    }
}
