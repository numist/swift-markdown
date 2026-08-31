/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for a softbreak-spanning inline WRAPPER (emphasis/strong/link) inside a MULTI-LINE
/// setext heading whose content is flattened into one arena chunk.
///
/// The shipped (flag-off, spec-correct) parser reports the wrapper's end at the closer's TRUE
/// physical column - the continuation line is NOT re-indented - so the wrapper end stays on the
/// closer's own line and never spills onto the `====` / `----` underline that follows. This is the
/// flag-off guardrail for the flattened-setext wrapper-end mapping: cmark's continuation re-indent
/// (which the flag-on `setextwrap-*` fuzzer pairs cover) pushes the closer's re-indented column past
/// its physical line's byte extent, and the byte projection of that end used to overshoot onto the
/// underline line. That mapping is corrected unconditionally (see `stampInline`); flag-off there is
/// no re-indent, so the end must be the plain true column proven here.
@Suite("Setext heading multi-line wrapper source ranges (spec-correct)")
struct SetextWrapperEndRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    private func ranges(in src: String) throws -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
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

    @Test("emphasis wrapper end keeps the closer's true column, not the underline line")
    func emphasisWrapperEnd() throws {
        // "  Foo *bar" on line 1, "baz*" on line 2, "====" underline on line 3. The heading's content
        // column is 3 (from line 1's two-space indent). The emphasis `*bar\nbaz*` spans the softbreak;
        // its closer `*` is the 4th byte of line 2, so spec-correct it is at TRUE column 4 and the
        // wrapper's half-open end is @2:5 - NOT the re-indented @2:7, and NOT a line-3 overshoot onto
        // the `====` underline (the flag-on `setextwrap-notab` fuzzer pair).
        let ranges = try ranges(in: "  Foo *bar\nbaz*\n====")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 3, "expected Foo / bar / baz text nodes")

        try #require(firstRange(.heading(level: 1), in: ranges) != nil)
        #expect(firstRange(.heading(level: 1), in: ranges)?.lowerBound == Pos(line: 1, column: 3))

        let emph = try #require(firstRange(.emphasis, in: ranges))
        #expect(emph.lowerBound == Pos(line: 1, column: 7))    // opening `*`
        #expect(emph.upperBound == Pos(line: 2, column: 5))    // closer `*` at true col 4, half-open 5

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "Foo "
        #expect(texts[2]?.lowerBound == Pos(line: 2, column: 1))   // "baz" at its true column
        #expect(texts[2]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("strong wrapper end keeps the closer's true column, not the underline line")
    func strongWrapperEnd() throws {
        // As above with `**bar\nbaz**`: the closer `**` occupies true cols 4-5 of line 2, so the
        // wrapper's half-open end is @2:6 - NOT the re-indented @2:8, and NOT a line-3 overshoot.
        let ranges = try ranges(in: "  Foo **bar\nbaz**\n====")
        try #require(ranges.contains { $0.kind == .strong })

        let strong = try #require(firstRange(.strong, in: ranges))
        #expect(strong.lowerBound == Pos(line: 1, column: 7))
        #expect(strong.upperBound == Pos(line: 2, column: 6))
    }

    @Test("link wrapper end keeps the closer's true column, not the underline line")
    func linkWrapperEnd() throws {
        // As above with `[bar\nbaz](/u)`: the closer `)` is the 8th byte of line 2, so the wrapper's
        // half-open end is @2:9 - NOT the re-indented @2:11, and NOT a line-3 overshoot. Also proves the
        // arena-backed destination `/u` unescapes without indexing the source buffer at an arena offset.
        let ranges = try ranges(in: "  Foo [bar\nbaz](/u)\n====")
        try #require(ranges.contains { $0.kind == .link })

        let link = try #require(firstRange(.link, in: ranges))
        #expect(link.lowerBound == Pos(line: 1, column: 7))
        #expect(link.upperBound == Pos(line: 2, column: 9))
    }
}
