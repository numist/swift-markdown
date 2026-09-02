/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// GFM single-column table detection. A single-column table is one whose delimiter row parses to
/// exactly one column (e.g. `|-`, `-|`, `|-|`, or a pipe-less `:-`). cmark-gfm accepts these
/// (`extensions/table.c`: a table forms when the delimiter row scans to >= 1 column and the header
/// column count equals it — there is NO requirement that the header line contain a pipe), so the
/// rewrite must too. This holds on all three detection paths: the zero-copy contiguous fast path, the
/// materialized-chunk path, and the non-contiguous segment path (a top-level row with leading
/// whitespace, or content nested in a block quote / list).
///
/// A pipe-less dash-only second line (`-`, `--`, `---`) is NOT a table: cmark's block-start chain
/// (`open_new_blocks` in `blocks.c`) matches a setext-heading underline BEFORE it reaches the table
/// extension, so such a paragraph becomes a heading and never reaches table detection. The rewrite
/// mirrors this: setext/thematic-break resolution happens during block parsing, before the paragraph
/// is offered to the table transform. These negative controls pin that boundary.
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
    /// `.none` when the document has no blocks. Parsed with `.tables` but WITHOUT
    /// `.cmarkBugCompatibility`: single-column detection is an unconditional structural `[fix]`, so it
    /// must hold with the deliverable's flags.
    private func firstBlock(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) throws -> Block {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc -> Block in
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
    ) throws -> Block? {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc -> Block? in
            firstTableShape(in: doc.root)
        }
    }

    @Test("a leading-pipe single-column delimiter row forms a table")
    func leadingPipe() throws {
        let block = try firstBlock("a\n|-")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.none])
    }

    @Test("a trailing-pipe single-column delimiter row forms a table")
    func trailingPipe() throws {
        let block = try firstBlock("a\n-|")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.none])
    }

    @Test("a both-pipes single-column delimiter row forms a table")
    func bothPipes() throws {
        let block = try firstBlock("a\n|-|")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.none])
    }

    @Test("a pipe-less colon single-column delimiter row forms a left-aligned table")
    func pipelessColonLeft() throws {
        // cmark forms a table here (`a\n:-`): the pipe-less DASH exclusion is setext precedence, not a
        // pipe requirement, and `:-` is not a setext underline. This is the case the task's simplified
        // "single column needs a pipe" model gets wrong.
        let block = try firstBlock("a\n:-")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.left])
    }

    @Test("a pipe-less centered single-column delimiter row forms a centered table")
    func pipelessColonCenter() throws {
        let block = try firstBlock("a\n:-:")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.center])
    }

    @Test("single-column alignment markers set the column alignment")
    func alignmentVariants() throws {
        #expect(try firstBlock("a\n|:-").alignments == [.left])
        #expect(try firstBlock("a\n|-:|").alignments == [.right])
        #expect(try firstBlock("a\n|:-:|").alignments == [.center])
    }

    @Test("a single-column table carries body rows")
    func bodyRows() throws {
        let block = try firstBlock("a\n|-|\nb\nc")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.bodyRows == [["b"], ["c"]])
    }

    @Test("a top-level row with leading whitespace still forms a single-column table (segment path)")
    func leadingWhitespaceDelimiterRow() throws {
        // ` :-` arrives as a re-indented segment list, not a contiguous source range; the detection
        // gate must scan the delimiter line, not the (pipe-less) header.
        let block = try firstBlock("a\n :-")
        try #require(block.kind == .table, "expected a single-column table, got \(block.kind)")
        #expect(block.headerCells == ["a"])
        #expect(block.alignments == [.left])
    }

    @Test("a single-column table nested in a block quote forms (segment path)")
    func nestedBlockQuoteSingleColumn() throws {
        // Nested content is a materialized segment list; the same gate must admit its pipe-less header.
        // (Nested-container source positions are a separately deferred class; this asserts structure.)
        let table = try #require(try firstTable("> a\n> :-"), "expected a nested single-column table")
        #expect(table.headerCells == ["a"])
        #expect(table.alignments == [.left])
    }

    @Test("a pipe-less dash-only second line stays a setext heading, not a table")
    func pipelessDashIsSetext() throws {
        // `-`, `--`, `---` are setext underlines; setext resolution precedes table detection, so these
        // never become tables. This must stay true after relaxing the header-pipe gate.
        #expect(try firstBlock("a\n-").kind == .heading)
        #expect(try firstBlock("a\n--").kind == .heading)
        #expect(try firstBlock("a\n---").kind == .heading)
    }

    @Test("a second line that is not a delimiter row stays a paragraph")
    func nonDelimiterStaysParagraph() throws {
        // Guard against over-eager detection: an ordinary two-line paragraph must not become a table.
        #expect(try firstBlock("a\nb").kind == .paragraph)
        #expect(try firstBlock("a|b\nc|d").kind == .paragraph)
    }

    @Test("a multi-column table is unaffected")
    func multiColumnRegression() throws {
        let block = try firstBlock("a|b\n-|-")
        try #require(block.kind == .table, "expected a two-column table, got \(block.kind)")
        #expect(block.headerCells == ["a", "b"])
        #expect(block.alignments == [.none, .none])
    }
}
