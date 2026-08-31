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

    @Test("lazy continuation into a blockquote keeps its true column, not the block content column")
    func lazyBlockquoteContinuation() throws {
        // "> bar" on line 1, "baz" on line 2 with NO `>` marker: a LAZY continuation absorbed into
        // the blockquote paragraph. The paragraph's content column is 3 (from line 1's `bar`). Because
        // line 2 has no marker or leading whitespace stripped, its content is source-contiguous with
        // line 1, so the parser keeps the whole run zero-copy on one `.lazy` range. Spec-correct, `baz`
        // keeps its TRUE column: line 2 starts at column 1, so `baz` is @2:1-2:4 - consistent with the
        // paragraph/block-quote end @2:4. cmark re-indents `baz` to the fixed content column 3 and
        // reports @2:3-2:6, an end (2:6) past the paragraph end (2:4) - the `s24-lazy-bq` fuzzer pair,
        // flag-on. This case is the flag-off guardrail for the lazy-contiguity re-indent path.
        let ranges = try ranges(in: "> bar\nbaz")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 2, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "baz" at its true column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("multi-line lazy continuation keeps each line's true column")
    func lazyMultilineContinuation() throws {
        // "> bar" then two marker-less lazy continuation lines "baz" and "qux". The paragraph's content
        // column is 3 (from line 1's `bar`). Spec-correct, each continuation line keeps its TRUE column:
        // both start at column 1, so `baz` is @2:1-2:4 and `qux` is @3:1-3:4 - consistent with the
        // paragraph/block-quote end @3:4. cmark re-indents both to the fixed content column 3, reporting
        // `baz` @2:3-2:6 and `qux` @3:3-3:6 (the `s24-lazy-multi` fuzzer pair, flag-on). This case guards
        // the flag-off multi-line path where a re-indented MIDDLE line's end would otherwise cross a
        // physical line boundary flag-on.
        let ranges = try ranges(in: "> bar\nbaz\nqux")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 3)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 3, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 3, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "baz" at its true column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
        #expect(texts[2]?.lowerBound == Pos(line: 3, column: 1))   // "qux" at its true column
        #expect(texts[2]?.upperBound == Pos(line: 3, column: 4))
    }

    @Test("lazy continuation into a blockquote with leading whitespace keeps its true column")
    func lazyBlockquoteContinuationWithLeadingWhitespace() throws {
        // "> foo" on line 1, "  baz" on line 2 with NO `>` marker but TWO leading spaces: a LAZY
        // continuation absorbed into the blockquote paragraph. The paragraph's content column is 3
        // (from line 1's `foo`). Spec-correct, `baz` keeps its TRUE column: the two spaces are cols
        // 1-2, so `baz` is @2:3-2:6 - consistent with the paragraph/block-quote end @2:6, and the
        // re-indent is off entirely. cmark, flag-on, does NOT strip a lazy line's leading whitespace
        // (unlike a matched continuation), so it reports `baz` at `true_col + block_offset` = @2:5-2:8
        // (the `bqlazy-2sp` fuzzer pair). This is the flag-off guardrail proving the flag-on
        // preserve-leading-whitespace base is quarantined behind `.cmarkBugCompatibility`.
        let ranges = try ranges(in: "> foo\n  baz")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 2, column: 6))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 6))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 3))   // "baz" at its true column, NOT @2:5
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 6))
    }

    @Test("lazy continuation into a list item keeps its true column, not the block content column")
    func lazyListContinuation() throws {
        // "- foo" on line 1, " bar" on line 2 (ONE leading space): the item's content column is 2
        // (marker `-` + one space), but line 2 is indented only 1, so the item prefix fails to match and
        // `bar` is a LAZY continuation of the item's paragraph. The paragraph's content column is 2 (from
        // line 1's `foo`). Spec-correct, `bar` keeps its TRUE column: the one space is col 1, so `bar`
        // is @2:2-2:5 - consistent with the paragraph/list/item end @2:5. cmark, flag-on, does NOT strip a
        // lazy line's leading whitespace, so it reports `bar` at `residual + block_offset` = @2:4-2:7 (the
        // `llg-list-1sp` fuzzer pair). This is the flag-off guardrail for the generalized lazy re-indent
        // over LIST containers.
        let ranges = try ranges(in: "- foo\n bar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        let listRange = ranges.first { if case .list = $0.kind { return true } else { return false } }?.range
        #expect(listRange?.lowerBound == Pos(line: 1, column: 1))
        #expect(listRange?.upperBound == Pos(line: 2, column: 5))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 5))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 2))   // "bar" at its true column, NOT @2:4
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 5))
    }

    @Test("lazy continuation into a nested blockquote keeps its true column, not the block content column")
    func lazyNestedBlockquoteContinuation() throws {
        // "> > foo" on line 1, ">  baz" on line 2: the outer `> ` prefix matches (consuming cols 1-2) but
        // the inner block quote has no `>`, so `baz` is a LAZY continuation of the inner paragraph. The
        // paragraph's content column is 5 (from line 1's `foo`). Spec-correct, `baz` keeps its TRUE column:
        // `>` is col 1, the two spaces are cols 2-3, so `baz` is @2:4-2:7 - consistent with the
        // paragraph/block-quote end @2:7. cmark, flag-on, preserves the residual whitespace left after the
        // matched outer prefix (one space, between the consumed `> ` and `baz`) and reports `baz` at
        // `residual + block_offset` = @2:6-2:9 (the `llg-nest-bq` fuzzer pair). This is the flag-off
        // guardrail for the generalized lazy re-indent when an OUTER container consumed columns first.
        let ranges = try ranges(in: "> > foo\n>  baz")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        let quotes = ranges.filter { $0.kind == .blockQuote }.map { $0.range }
        try #require(texts.count == 2)
        try #require(quotes.count == 2)

        #expect(quotes[0]?.lowerBound == Pos(line: 1, column: 1))   // outer block quote
        #expect(quotes[0]?.upperBound == Pos(line: 2, column: 7))
        #expect(quotes[1]?.lowerBound == Pos(line: 1, column: 3))   // inner block quote
        #expect(quotes[1]?.upperBound == Pos(line: 2, column: 7))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 5))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 7))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 5))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 4))   // "baz" at its true column, NOT @2:6
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 7))
    }
}
