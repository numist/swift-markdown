/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Adjacent text in a table cell, including bracket literals, decoded entity references and smart
/// punctuation, forms a single `.text` node. Its literal is the concatenation of the runs, and its source
/// range spans from the first run's start to the last run's end.
@Suite("Table cell text consolidation")
struct TableCellTextConsolidationTests {

    /// A single inline child of a cell, projected to copyable values (nodes are borrowing).
    private struct Child {
        let kind: MarkdownNode.Kind
        let literal: String?
        /// (startLine, startColumn, endLine, endColumn) or `nil` when the node carries no source range.
        let range: (Int, Int, Int, Int)?
        /// Kinds of this child's own children (e.g. the `.text` inside an `.emphasis`).
        let grandchildKinds: [MarkdownNode.Kind]
        /// Literals of this child's own children, concatenated.
        let grandchildLiterals: String
    }

    /// Rows of cells of direct inline children for the first table in `source`.
    private func tableCellChildren(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) -> [[[Child]]] {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> [[[Child]]] in
            var rows: [[[Child]]] = []
            var found = false
            doc.root.children.forEach { block in
                if found || block.kind != .table { return }
                found = true
                block.children.forEach { row in
                    guard case .tableRow = row.kind else { return }
                    var cells: [[Child]] = []
                    row.children.forEach { cell in
                        guard case .tableCell = cell.kind else { return }
                        var children: [Child] = []
                        cell.children.forEach { inline in
                            let range: (Int, Int, Int, Int)? = inline.sourceRange.map {
                                ($0.lowerBound.line, $0.lowerBound.column, $0.upperBound.line, $0.upperBound.column)
                            }
                            var gkinds: [MarkdownNode.Kind] = []
                            var gliterals = ""
                            inline.children.forEach { grand in
                                gkinds.append(grand.kind)
                                if let l = grand.literal() { gliterals += l }
                            }
                            children.append(Child(
                                kind: inline.kind,
                                literal: inline.literal(),
                                range: range,
                                grandchildKinds: gkinds,
                                grandchildLiterals: gliterals
                            ))
                        }
                        cells.append(children)
                    }
                    rows.append(cells)
                }
            }
            return rows
        }
    }

    private static let posOpts: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]

    // MARK: - Merged runs

    @Test("a bracket literal merges with adjacent text in a cell")
    func bracketMergesWithText() throws {
        let rows = tableCellChildren("[t\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: cell must have exactly one inline child, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        #expect(cell[0].literal == "[t")
        #expect(cell[0].range.map { $0 == (1, 1, 1, 3) } == true)
    }

    /// The source range covers the entity reference's five source bytes, not its one-byte decoded form.
    @Test("a decoded entity merges with surrounding text in a cell")
    func entityMergesWithText() throws {
        let rows = tableCellChildren("a&amp;t\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: cell must have exactly one inline child, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        #expect(cell[0].literal == "a&t")
        #expect(cell[0].range.map { $0 == (1, 1, 1, 8) } == true)
    }

    @Test("entity + bracket + smart quote form one text node in a cell")
    func entityBracketSmartQuoteMerge() throws {
        let rows = tableCellChildren("[\"&amp;\n|-", options: [.tables, .sourcePosition, .smart])
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: cell must coalesce to one inline child, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        let literal = try #require(cell[0].literal, "fixture: merged node must be text")
        // Checks the ends rather than transcribing the curly quote.
        #expect(literal.hasPrefix("["))
        #expect(literal.hasSuffix("&"))
        #expect(cell[0].range.map { $0 == (1, 1, 1, 8) } == true)
    }

    // MARK: - Boundaries

    @Test("plain cell text is a single node")
    func plainCellTextSingleNode() throws {
        let rows = tableCellChildren("ab\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        #expect(cell.count == 1)
        #expect(cell[0].literal == "ab")
    }

    @Test("emphasis is not merged into adjacent cell text")
    func emphasisBoundaryNotMerged() throws {
        let rows = tableCellChildren("a*b*c\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.map(\.kind).contains(.emphasis), "fixture: the `*b*` run must parse as emphasis")
        #expect(cell.map(\.kind) == [.text, .emphasis, .text])
        #expect(cell[0].literal == "a")
        #expect(cell[2].literal == "c")
        #expect(cell[1].grandchildKinds == [.text])
        #expect(cell[1].grandchildLiterals == "b")
    }

    // MARK: - Rows and escaped pipes

    @Test("each row's cells consolidate independently")
    func multiRowConsolidation() throws {
        let rows = tableCellChildren("a|b\n-|-\n[x|]y\nm[|n]", options: Self.posOpts)
        try #require(rows.count == 3, "fixture: expected a header row and two body rows, got \(rows.count)")
        try #require(rows[1].count == 2 && rows[2].count == 2, "fixture: two cells per body row")
        #expect(rows[1][0].count == 1 && rows[1][0][0].literal == "[x")
        #expect(rows[1][1].count == 1 && rows[1][1][0].literal == "]y")
        #expect(rows[2][0].count == 1 && rows[2][0][0].literal == "m[")
        #expect(rows[2][1].count == 1 && rows[2][1][0].literal == "n]")
    }

    @Test("a cell with an escaped pipe merges the pipe with its neighbouring text")
    func escapedPipeCellConsolidates() throws {
        let rows = tableCellChildren("x\\|[y\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: escaped-pipe cell must coalesce to one node, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        #expect(cell[0].literal == "x|[y")
        let range = try #require(cell[0].range, "fixture: merged node must be positioned")
        #expect(range.0 == 1 && range.1 == 1)
    }

    /// Leading whitespace is trimmed from the cell, so the merged node starts at column 2.
    @Test("a cell with leading whitespace merges its text runs")
    func leadingWhitespaceCellConsolidates() throws {
        let rows = tableCellChildren("a|b\n-|-\n [x|y", options: Self.posOpts)
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 2, "fixture: expected two body cells, got \(rows[1].count)")
        let cell = rows[1][0]
        try #require(cell.count == 1, "fixture: cell must coalesce to one node, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        #expect(cell[0].literal == "[x")
        #expect(cell[0].range.map { $0 == (3, 2, 3, 4) } == true)
    }
}
