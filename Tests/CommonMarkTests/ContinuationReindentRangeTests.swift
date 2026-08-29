/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for a multi-line paragraph's *continuation lines* - lines that continue a
/// paragraph and carry more leading whitespace than the paragraph's fixed content column.
///
/// The shipped (flag-off, spec-correct) parser reports each continuation line's inline content at
/// its TRUE physical column, keeping that line's own leading whitespace. cmark-gfm instead
/// re-indents the continuation: it fixes the paragraph's content column from the FIRST line and
/// maps every continuation line's surviving content to that fixed column, discarding the line's own
/// leading whitespace - so a more-indented continuation line's text lands at the wrong (leftward)
/// column, and the resulting tree is internally inconsistent (the text node's end column can sit
/// before its own paragraph's end column, which is computed from the true line width). That
/// inconsistency is the tell that this is a cmark bug, not spec behavior. cmark's re-indent is the
/// `.cmarkBugCompatibility` quirk, covered by the `s560-*` / `s12-*` / `b1-multiseg-*` fuzzer
/// regression pairs (which parse flag-on); this suite is the flag-off guardrail proving the default
/// parser is spec-correct.
@Suite("Paragraph continuation-line source ranges (spec-correct)")
struct ContinuationReindentRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// DFS-collect every node's kind and source range when `src` is parsed spec-correct.
    private func ranges(in src: String) throws -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
    }

    /// The first node whose kind equals `kind`, in DFS order.
    private func firstRange(
        _ kind: MarkdownNode.Kind,
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Range<Pos>? {
        ranges.first { $0.kind == kind }?.range
    }

    @Test("top-level continuation keeps its true column, not the block content column")
    func topLevelContinuation() throws {
        // "foo" on line 1, "   bar" on line 2 (three spaces before `bar`). The paragraph's content
        // column is 0 (top-level). Spec-correct, `bar` keeps its true column: it starts at column 4
        // (after the three spaces) and ends at 7 - consistent with the paragraph/document end @2:7.
        // cmark re-indents `bar` to content column 0 and reports @2:1-2:4, an end (2:4) that sits
        // before the paragraph end (2:7) - the `s560-indented-continuation` fuzzer pair, flag-on.
        let ranges = try ranges(in: "foo\n   bar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 2, column: 7))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 7))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 4))   // "bar" at its true column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 7))
    }

    @Test("blockquote continuation keeps its true column, not the block content column")
    func blockquoteContinuation() throws {
        // "> foo" on line 1, ">    bar" on line 2 (marker `>`, four spaces, then `bar`). The
        // paragraph's content column is 3 (from line 1's `foo`). Spec-correct, `bar` keeps its true
        // column: `>` is col 1, the four spaces are cols 2-5, so `bar` starts at column 6 and ends
        // at 9 - consistent with the paragraph/block-quote end @2:9. cmark re-indents `bar` to the
        // fixed content column 3, discarding line 2's four leading spaces, and reports @2:3-2:6.
        let ranges = try ranges(in: "> foo\n>    bar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 2, column: 9))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 9))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 6))   // "bar" at its true column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 9))
    }
}
