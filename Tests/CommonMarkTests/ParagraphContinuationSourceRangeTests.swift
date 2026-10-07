/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A paragraph continuation line's text starts at the line's first non-whitespace byte, wherever
/// that falls relative to the paragraph's first line. Paragraphs strip the line's leading
/// whitespace from the raw content, so the source range begins after it.
@Suite("Paragraph continuation line source ranges")
struct ParagraphContinuationSourceRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// Every node's kind and source range, in depth-first order.
    private func ranges(in src: String) -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
    }

    /// The source range of the first node whose kind equals `kind`, in depth-first order.
    private func firstRange(
        _ kind: MarkdownNode.Kind,
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Range<Pos>? {
        ranges.first { $0.kind == kind }?.range
    }

    @Test("top-level continuation line text starts after its leading whitespace")
    func topLevelContinuation() throws {
        let ranges = ranges(in: "foo\n   bar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 2, column: 7))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 7))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 4))
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 7))
    }

    @Test("block quote continuation line text starts after its leading whitespace")
    func blockquoteContinuation() throws {
        // The block quote marker consumes `>` and one space; the remaining three spaces are
        // stripped as paragraph leading whitespace, so `bar` starts at column 6.
        let ranges = ranges(in: "> foo\n>    bar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 2, column: 9))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 9))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 6))
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 9))
    }

    @Test("lazy continuation line in a block quote starts at column 1")
    func lazyBlockquoteContinuation() throws {
        let ranges = ranges(in: "> bar\nbaz")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 2, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("consecutive lazy continuation lines each start at column 1")
    func lazyMultilineContinuation() throws {
        let ranges = ranges(in: "> bar\nbaz\nqux")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 3)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 3, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 3, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
        #expect(texts[2]?.lowerBound == Pos(line: 3, column: 1))
        #expect(texts[2]?.upperBound == Pos(line: 3, column: 4))
    }

    @Test("indented lazy continuation line in a block quote starts after its leading whitespace")
    func lazyBlockquoteContinuationWithLeadingWhitespace() throws {
        let ranges = ranges(in: "> foo\n  baz")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.blockQuote, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.blockQuote, in: ranges)?.upperBound == Pos(line: 2, column: 6))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 6))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 3))
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 6))
    }

    @Test("lazy continuation line in a list item starts after its leading whitespace")
    func lazyListContinuation() throws {
        // One space is less than the item's content indent of two, so ` bar` is a lazy continuation
        // line (List items).
        let ranges = ranges(in: "- foo\n bar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        let listRange = ranges.first { if case .list = $0.kind { return true } else { return false } }?.range
        #expect(listRange?.lowerBound == Pos(line: 1, column: 1))
        #expect(listRange?.upperBound == Pos(line: 2, column: 5))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 5))

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 2))
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 5))
    }

    @Test("lazy continuation line in a nested block quote starts after its leading whitespace")
    func lazyNestedBlockquoteContinuation() throws {
        // Line 2 matches the outer block quote marker only, so `baz` is a lazy continuation line of
        // the inner block quote's paragraph.
        let ranges = ranges(in: "> > foo\n>  baz")
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
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 4))
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 7))
    }
}
