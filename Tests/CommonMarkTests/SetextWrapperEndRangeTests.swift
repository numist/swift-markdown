/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of emphasis, strong emphasis and links that span a soft line break inside a
/// multi-line setext heading with an indented first line. Each ends just past its closing delimiter on
/// that delimiter's own line, before the underline.
@Suite("Setext heading multi-line wrapper source ranges")
struct SetextWrapperEndRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    private func ranges(in src: String) -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
    }

    private func firstRange(
        _ kind: MarkdownNode.Kind,
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Range<Pos>? {
        ranges.first { $0.kind == kind }?.range
    }

    @Test("emphasis spanning lines ends on the closer's line, not the underline line")
    func emphasisWrapperEnd() throws {
        let ranges = ranges(in: "  Foo *bar\nbaz*\n====")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 3, "expected Foo / bar / baz text nodes")

        try #require(firstRange(.heading(level: 1), in: ranges) != nil)
        #expect(firstRange(.heading(level: 1), in: ranges)?.lowerBound == Pos(line: 1, column: 3))

        let emph = try #require(firstRange(.emphasis, in: ranges))
        #expect(emph.lowerBound == Pos(line: 1, column: 7))    // opening `*`
        #expect(emph.upperBound == Pos(line: 2, column: 5))    // past the closing `*`

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "Foo "
        #expect(texts[2]?.lowerBound == Pos(line: 2, column: 1))   // "baz"
        #expect(texts[2]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("strong emphasis spanning lines ends on the closer's line, not the underline line")
    func strongWrapperEnd() throws {
        let ranges = ranges(in: "  Foo **bar\nbaz**\n====")
        try #require(ranges.contains { $0.kind == .strong })

        let strong = try #require(firstRange(.strong, in: ranges))
        #expect(strong.lowerBound == Pos(line: 1, column: 7))
        #expect(strong.upperBound == Pos(line: 2, column: 6))
    }

    @Test("link spanning lines ends on the closer's line, not the underline line")
    func linkWrapperEnd() throws {
        let ranges = ranges(in: "  Foo [bar\nbaz](/u)\n====")
        try #require(ranges.contains { $0.kind == .link })

        let link = try #require(firstRange(.link, in: ranges))
        #expect(link.lowerBound == Pos(line: 1, column: 7))
        #expect(link.upperBound == Pos(line: 2, column: 9))
    }
}
