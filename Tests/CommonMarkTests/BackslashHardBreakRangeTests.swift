/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of inline nodes after a hard line break made by a backslash at the end of a line. Each node after
/// the break lies on its own line, at its own source column.
@Suite("Backslash hard line break source ranges")
struct BackslashHardBreakRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The source ranges of every text node in `src`, in DFS order.
    private func textRanges(in src: String) -> [Range<Pos>?] {
        let ranges = MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.filter { $0.kind == .text }.map { $0.range }
    }

    @Test("text after a backslash hard line break starts on the next line")
    func textAfterBreakResetsToNextLine() throws {
        let texts = textRanges(in: "foo\\\nbar")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "bar"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("text after each backslash hard line break starts on its own line")
    func multipleBreaksEachReset() throws {
        let texts = textRanges(in: "a\\\nb\\\nc")
        try #require(texts.count == 3)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "a"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 2))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "b"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
        #expect(texts[2]?.lowerBound == Pos(line: 3, column: 1))   // "c"
        #expect(texts[2]?.upperBound == Pos(line: 3, column: 2))
    }

    @Test("an unmatched `~` after a backslash hard line break is text on its own line")
    func unmatchedTildeAfterBreak() throws {
        let texts = textRanges(in: "a\\\n~")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "a"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 2))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "~"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
    }
    // MARK: - Continuation lines with stripped indentation or prefixes

    @Test("text after a backslash break on an indented continuation line keeps its source column")
    func textAfterBreakOnIndentedContinuation() throws {
        let texts = textRanges(in: "foo\\\n bar")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 2))   // "bar"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 5))
    }

    @Test("a wider continuation indent shifts the source column")
    func textAfterBreakOnWiderIndent() throws {
        let texts = textRanges(in: "foo\\\n     bar")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 6))   // "bar"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 9))
    }

    @Test("text after a backslash break inside a block quote keeps its source column")
    func textAfterBreakInBlockquote() throws {
        let texts = textRanges(in: "> a\\\n> b")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "a"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 3))   // "b"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("text after a backslash break on a lazy continuation line keeps its source column")
    func textAfterBreakOnLazyListContinuation() throws {
        // Lines 2 and 3 are lazy continuation lines (Block quotes) of the list item's paragraph.
        let texts = textRanges(in: "- b\n \\\nc")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "b"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 3, column: 1))   // "c"
        #expect(texts[1]?.upperBound == Pos(line: 3, column: 2))
    }
}
