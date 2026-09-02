/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Adjacent inline `.text` pieces inside a GFM table cell must coalesce into a single `.text` node, the
/// same way the paragraph inline path does — cmark runs `cmark_consolidate_text_nodes` over every node's
/// inlines uniformly (`src/iterator.c`), including table cells (`extensions/table.c` builds cell inlines
/// through the shared inline parser). The rewrite's inline parser emits bracket literals (`[`/`]`),
/// decoded entities, and smart-quote glyphs as their OWN text nodes; only a post-parse consolidation pass
/// merges them. The paragraph path consolidates after `parseInline`; a table cell is inline-parsed on the
/// table path, so it must consolidate there too. This is a differential-qualification `[fix]` tracked
/// unconditionally (adjacent text nodes should always be one node), NOT gated on `.cmarkBugCompatibility`.
///
/// The merged node's literal is the concatenation of the runs, and its source range spans the first run's
/// start through the last run's end. Columns are 1-based and half-open on the end, matching the
/// `debugDescription` surface the differential fuzzer compares.
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
    ) throws -> [[[Child]]] {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc -> [[[Child]]] in
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

    // MARK: - Bracket literal (RED without the fix)

    /// A bracket literal adjacent to text merges into one `.text` node spanning both, with source
    /// positions on. Header cell `[t` of `[t\n|-` → one `Text "[t"` at 1:1–1:3.
    @Test("a bracket literal merges with adjacent text in a cell (positions on)")
    func bracketMergesWithText() throws {
        let rows = try tableCellChildren("[t\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: cell must have exactly one inline child, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        #expect(cell[0].literal == "[t")
        #expect(cell[0].range.map { $0 == (1, 1, 1, 3) } == true)
    }

    /// PHASE-0: consolidation is UNCONDITIONAL — it fires identically WITH and WITHOUT
    /// `.cmarkBugCompatibility` (there is no spec-correct behavior that over-splitting protects; adjacent
    /// text nodes should always be one node). Parsing the same input under each flag state must yield the
    /// same single merged node and range.
    @Test("consolidation is identical with and without .cmarkBugCompatibility")
    func consolidationUnconditionalAcrossCompatFlag() throws {
        let withFlag = try tableCellChildren("[t\n|-", options: [.tables, .sourcePosition, .cmarkBugCompatibility])
        let withoutFlag = try tableCellChildren("[t\n|-", options: Self.posOpts)
        try #require(withFlag.first?.first != nil && withoutFlag.first?.first != nil,
                     "fixture: expected a header cell under both flag states")
        // Both consolidate to one `Text "[t"` at 1:1–1:3 — the flag does not gate the merge.
        #expect(withFlag[0][0].count == 1)
        #expect(withoutFlag[0][0].count == 1)
        #expect(withFlag[0][0].first?.literal == "[t")
        #expect(withoutFlag[0][0].first?.literal == "[t")
        #expect(withFlag[0][0].first?.range.map { $0 == (1, 1, 1, 3) } == true)
        #expect(withoutFlag[0][0].first?.range.map { $0 == (1, 1, 1, 3) } == true)
    }

    /// A decoded entity merges with the surrounding text. `a&amp;t` → one `Text "a&t"` at 1:1–1:8
    /// (the entity's raw source width, 5 bytes, is preserved in the range even though it decodes to `&`).
    @Test("a decoded entity merges with surrounding text in a cell")
    func entityMergesWithText() throws {
        let rows = try tableCellChildren("a&amp;t\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: cell must have exactly one inline child, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        #expect(cell[0].literal == "a&t")
        #expect(cell[0].range.map { $0 == (1, 1, 1, 8) } == true)
    }

    /// A cell mixing an entity, a bracket literal, and a smart-quote glyph coalesces to one `.text` node
    /// spanning the whole cell content (minimal analogue of the `tblcons-orig` fuzzer artifact). The exact
    /// merged glyph sequence is validated end-to-end by that oracle pair; here we pin the structural
    /// property (one node) and the preserved range. `.smart` turns the `"` into a curly glyph, its own
    /// text node pre-consolidation.
    @Test("entity + bracket + smart-quote coalesce to one text node in a cell")
    func entityBracketSmartQuoteMerge() throws {
        // Cell content `["&amp;` (7 source bytes → columns 1–7, half-open end 8): `[` bracket literal,
        // `"` smart-quote glyph, `&amp;` decoded entity — three separate text nodes before consolidation.
        let rows = try tableCellChildren("[\"&amp;\n|-", options: [.tables, .sourcePosition, .smart])
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: cell must coalesce to one inline child, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        let literal = try #require(cell[0].literal, "fixture: merged node must be text")
        // Bounds pin the merge without transcribing the smart-quote glyph: begins with the bracket,
        // ends with the decoded ampersand.
        #expect(literal.hasPrefix("["))
        #expect(literal.hasSuffix("&"))
        #expect(cell[0].range.map { $0 == (1, 1, 1, 8) } == true)
    }

    // MARK: - Controls (GREEN before and after the fix)

    /// Plain contiguous text in a cell is already a single node (nothing to merge) — the boundary control.
    @Test("plain cell text is a single node")
    func plainCellTextSingleNode() throws {
        let rows = try tableCellChildren("ab\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        #expect(cell.count == 1)
        #expect(cell[0].literal == "ab")
    }

    /// Only ADJACENT `.text` siblings merge: an emphasis run between two text runs stays a separate node,
    /// and the text on either side is NOT pulled across it. Cell `a*b*c` → `Text "a"`, `Emphasis`, `Text
    /// "c"` (three children), with the emphasis wrapping its own `Text "b"`.
    @Test("emphasis is not merged into adjacent cell text")
    func emphasisBoundaryNotMerged() throws {
        let rows = try tableCellChildren("a*b*c\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.map(\.kind).contains(.emphasis), "fixture: the `*b*` run must parse as emphasis")
        #expect(cell.map(\.kind) == [.text, .emphasis, .text])
        #expect(cell[0].literal == "a")
        #expect(cell[2].literal == "c")
        // The emphasis wraps a single (already-plain) text node.
        #expect(cell[1].grandchildKinds == [.text])
        #expect(cell[1].grandchildLiterals == "b")
    }

    // MARK: - Multiple rows and the escaped-pipe (arena-copy) cell path

    /// Every row's cells consolidate independently — not just the header. Header `a|b`, body rows `[x|]y`
    /// and `m[|n]`: each two-column body cell coalesces its bracket-literal + text into one node.
    @Test("each row's cells consolidate independently")
    func multiRowConsolidation() throws {
        let rows = try tableCellChildren("a|b\n-|-\n[x|]y\nm[|n]", options: Self.posOpts)
        try #require(rows.count == 3, "fixture: expected a header row and two body rows, got \(rows.count)")
        try #require(rows[1].count == 2 && rows[2].count == 2, "fixture: two cells per body row")
        #expect(rows[1][0].count == 1 && rows[1][0][0].literal == "[x")
        #expect(rows[1][1].count == 1 && rows[1][1][0].literal == "]y")
        #expect(rows[2][0].count == 1 && rows[2][0][0].literal == "m[")
        #expect(rows[2][1].count == 1 && rows[2][1][0].literal == "n]")
    }

    /// The escaped-pipe cell path (a `\|` forces the arena-copy branch: content is unescaped into the
    /// arena and parsed from there with a run map) consolidates too. Cell `x\|[y` unescapes to `x|[y` →
    /// text `x`, text `|`, bracket `[`, text `y` — four nodes that merge to one `Text "x|[y"`.
    @Test("an escaped-pipe (arena-copy) cell consolidates its text runs")
    func escapedPipeCellConsolidates() throws {
        let rows = try tableCellChildren("x\\|[y\n|-", options: Self.posOpts)
        try #require(rows.first?.first != nil, "fixture: expected a header row with one cell")
        let cell = rows[0][0]
        try #require(cell.count == 1, "fixture: escaped-pipe cell must coalesce to one node, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        // Proves the `\|` was unescaped (a literal pipe survives) AND that the arena-copy path consolidated.
        #expect(cell[0].literal == "x|[y")
        // The merged node carries a source range starting at the cell's first column on line 1.
        let range = try #require(cell[0].range, "fixture: merged node must be positioned")
        #expect(range.0 == 1 && range.1 == 1)
    }

    /// The flattened (leading-whitespace, re-based) cell path also consolidates. A leading space on the
    /// body row makes the paragraph non-contiguous, so it materializes with an arena→source run map
    /// (`.flattened` mode) — a distinct arena-copy branch from the `\|`-escape one. The re-based body cell
    /// ` [x` still coalesces its bracket-literal + text into one `Text "[x"`. Under `.cmarkBugCompatibility`
    /// the leading whitespace re-bases invisibly (the cell starts at column 1, not its physical column 2);
    /// consolidation only unions the pre-stamped ranges, so the re-base is preserved.
    @Test("a flattened (leading-whitespace re-based) cell consolidates its text runs")
    func flattenedCellConsolidates() throws {
        let rows = try tableCellChildren("a|b\n-|-\n [x|y", options: [.tables, .sourcePosition, .cmarkBugCompatibility])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 2, "fixture: expected two body cells, got \(rows[1].count)")
        let cell = rows[1][0]
        try #require(cell.count == 1, "fixture: flattened cell must coalesce to one node, got \(cell.map(\.kind))")
        #expect(cell[0].kind == .text)
        #expect(cell[0].literal == "[x")
        // Re-based onto the body row: line 3, column 1 through 3 (the leading space is invisible).
        #expect(cell[0].range.map { $0 == (3, 1, 3, 3) } == true)
    }
}
