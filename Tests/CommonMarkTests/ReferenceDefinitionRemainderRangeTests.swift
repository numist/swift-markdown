/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of the content that follows link reference definitions at the start of a paragraph.
/// The remaining text keeps its own lines, and the paragraph or setext heading starts at its first byte.
@Suite("Reference-definition remainder source ranges")
struct ReferenceDefinitionRemainderRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// DFS-collect every node's kind and source range.
    private func ranges(in src: String) -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
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

    @Test("content after a one-line ref-def keeps its own line")
    func singleLineRefDef() throws {
        let ranges = ranges(in: "[foo]: /url\nbar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 1)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 2, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 2, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 2, column: 1))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("setext heading content after a one-line ref-def keeps its own line")
    func setextHeadingRefDef() throws {
        let ranges = ranges(in: "[foo]: /url\nbar\n===")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 1)

        #expect(firstRange(.heading(level: 1), in: ranges)?.lowerBound == Pos(line: 2, column: 1))
        #expect(firstRange(.heading(level: 1), in: ranges)?.upperBound == Pos(line: 3, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 2, column: 1))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("content after a multi-line-label ref-def keeps its own line")
    func multiLineLabelRefDef() throws {
        let ranges = ranges(in: "[\nfoo\n]: /url\nbar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 1)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 4, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 4, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 4, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 4, column: 1))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 4, column: 4))
    }

    @Test("every remaining line keeps its own line after a ref-def")
    func multipleRemainingLines() throws {
        let ranges = ranges(in: "[foo]: /url\nbar\nbaz")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 3, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 2, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 3, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 2, column: 1))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 2, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 3, column: 1))   // "baz"
        #expect(texts[1]?.upperBound == Pos(line: 3, column: 4))
    }

    @Test("nested inline content after a ref-def keeps its own line, whole subtree")
    func nestedInlineRemainder() throws {
        let ranges = ranges(in: "[foo]: /url\na *b* c")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 3)

        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 2, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 8))

        #expect(texts[0]?.lowerBound == Pos(line: 2, column: 1))   // "a "
        #expect(texts[0]?.upperBound == Pos(line: 2, column: 3))
        #expect(firstRange(.emphasis, in: ranges)?.lowerBound == Pos(line: 2, column: 3))   // "*b*"
        #expect(firstRange(.emphasis, in: ranges)?.upperBound == Pos(line: 2, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 4))   // inner "b"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 5))
        #expect(texts[2]?.lowerBound == Pos(line: 2, column: 6))   // " c"
        #expect(texts[2]?.upperBound == Pos(line: 2, column: 8))
    }

    @Test("a blank line between ref-def and content starts a separate paragraph")
    func blankSeparatorIsSeparateParagraph() throws {
        let ranges = ranges(in: "[foo]: /url\n\nbar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 1)

        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 3, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 3, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 3, column: 1))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 3, column: 4))
    }

    @Test("indented remainder lines after a ref-def keep their own lines")
    func indentedRemainderKeepsOwnLines() throws {
        let ranges = ranges(in: "[a]:\n/b\n c\n d")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 4, column: 3))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 3, column: 2))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 4, column: 3))

        #expect(texts[0]?.lowerBound == Pos(line: 3, column: 2))   // "c"
        #expect(texts[0]?.upperBound == Pos(line: 3, column: 3))
        #expect(texts[1]?.lowerBound == Pos(line: 4, column: 2))   // "d"
        #expect(texts[1]?.upperBound == Pos(line: 4, column: 3))
    }
}
