/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Coverage for source-position stamping of inline runs on the 2nd+ physical line of a **materialized**
/// (single-segment arena) multi-line contiguous run.
///
/// A paragraph whose first line satisfies a finalize-time matcher's necessary condition - a GFM-table
/// header `|`, or a leading `[` (ref-def / footnote / tasklist) - is flattened from its segment list into
/// one arena `Chunk` so the matchers can scan it contiguously (`BlockParser.segmentsCouldMatchMatcher` /
/// `flattenSegments`). When the paragraph turns out NOT to match (no delimiter row, not a ref-def), that
/// arena content is what reaches inline parsing. Its arena→source map (`ArenaRun`) tiles the content one
/// run per source-adjacent line group: a contiguous run (`t\n|`) carries `physicalOffset == sourceOffset`
/// (no re-indent), a later leading-whitespace line carries `physicalOffset != sourceOffset` (re-indented).
///
/// Stamping an interior-line run on the contiguous arena run must project onto the run's own physical line,
/// exactly like the multi-segment-source case (`MultiLineSegmentRangeTests`). A contiguous run maps its
/// source where its bytes sit (`ArenaRun.sourceOffset == physicalOffset`, no re-indent), so its byte
/// projection is already exact and lands on the run's own line. (Regression for the differential-fuzzer
/// `pipemid-*` pairs.)
@Suite("Materialized (arena) multi-line contiguous run - interior-line inline positions")
struct MaterializedInteriorLineRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    // The GFM extension set the public `Document(parsing:options:)` API enables by default
    // (`CommonMarkConverter`), plus source positions. `.tables` is load-bearing here: it is what makes
    // `segmentsCouldMatchMatcher` flatten a pipe-bearing paragraph into arena content (the path under
    // test). Without it the paragraph stays multi-segment source and the arena branch is never exercised.
    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .tables, .strikethrough, .tasklist, .tableSpans]
    private static let quirkOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .tables, .strikethrough, .tasklist, .tableSpans, .cmarkBugCompatibility]

    private func ranges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out
    }

    /// The deliverable (flag-OFF, spec-correct default): a pipe on an interior line of a materialized
    /// paragraph keeps its true byte-projected position - `|` at `@2:1-2:2`, on its own physical line.
    /// A future change to the arena stamping path must not regress this.
    @Test("flag-OFF: interior-line pipe is stamped @2:1-2:2")
    func specInteriorPipe() throws {
        let texts = try ranges("t\n|\n b", options: Self.specOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "t"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "|" (interior line)
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 3))   // "b" (spec: true column)
    }

    /// The deliverable, pipe on line 1 (a legitimate but failed table candidate, so still materialized):
    /// the interior-line `bar` keeps its true position `@2:1`.
    @Test("flag-OFF: interior line after a line-1 pipe is stamped @2:1-2:4")
    func specInteriorAfterLine1Pipe() throws {
        let texts = try ranges("|foo\nbar\n baz", options: Self.specOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 5))   // "|foo"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 4))   // "bar" (interior line)
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 5))   // "baz" (spec: true column)
    }

    /// Flag-ON (differential-fuzzer configuration). The `pipemid-*` oracle values (minted from cmark-gfm):
    /// each interior contiguous-line run keeps its own physical line's position; only the final
    /// re-indented line moves to column 1.
    @Test("flag-ON: interior-line pipe stamps on its own line, final line re-indents to col 1")
    func quirkInteriorPipe() throws {
        let texts = try ranges("t\n|\n b", options: Self.quirkOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "t"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "|" (interior line, own line)
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "b" re-indented to col 1
    }

    /// Flag-ON, pipe on line 1 (failed table candidate, still materialized): the interior `bar` stamps on
    /// line 2, the final re-indented `baz` moves to column 1.
    @Test("flag-ON: interior line after a line-1 pipe stamps on its own line")
    func quirkInteriorAfterLine1Pipe() throws {
        let texts = try ranges("|foo\nbar\n baz", options: Self.quirkOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 5))   // "|foo"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 4))   // "bar" on line 2
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 4))   // "baz" re-indented to col 1
    }
}
