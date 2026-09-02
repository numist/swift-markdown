/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for a GFM strikethrough whose opener and closer sit on different physical lines
/// (the run spans one or more soft breaks).
///
/// The deliverable reports such a strikethrough's END on the CLOSER's real physical line (the
/// byte-projected half-open end past the closer run). A single-line strikethrough's opener and closer
/// share a line, so it is unchanged. These are the deliverable (spec-correct) guardrails.
@Suite("Multi-line strikethrough source ranges")
struct MultiLineStrikethroughEndTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The flag-on (differential-fuzzer) configuration: the spec set plus `.cmarkBugCompatibility`.
    private static let quirkOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart, .cmarkBugCompatibility]

    /// The source range of the first `.strikethrough` node (DFS order) when `src` is parsed with
    /// `options`. Returns `nil` if no strikethrough forms, so callers can `#require` fixture sanity.
    private func strikethroughRange(in src: String, options: MarkdownDocument.ParseOptions) throws -> Range<Pos>? {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> Range<Pos>? in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            for entry in ranges where entry.kind == .strikethrough {
                return entry.range
            }
            return nil
        }
    }

    /// Every node kind in DFS order (for fixture-sanity assertions about nesting).
    private func kinds(in src: String, options: MarkdownDocument.ParseOptions) throws -> [MarkdownNode.Kind] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [MarkdownNode.Kind] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges.map(\.kind)
        }
    }

    @Test("flag-off: a two-line strikethrough ends on the closer's real line (spec-correct)")
    func twoLineSpecCorrect() throws {
        // `~~a` on line 1, `b~~` on line 2. Spec-correct the end is the closer run's half-open column
        // on its OWN line: the last `~` is at line 2 col 3 (b=1, ~=2, ~=3), so the half-open end is
        // @2:4 - the closer's real line.
        let range = try #require(try strikethroughRange(in: "~~a\nb~~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 4))
    }

    @Test("flag-off: a three-line strikethrough ends on the closer's real line (spec-correct)")
    func threeLineSpecCorrect() throws {
        // `~~a` / `bb` / `cc~~`. The closer `~~` ends at line 3 col 5 (c=1, c=2, ~=3, ~=4, half-open 5).
        let range = try #require(try strikethroughRange(in: "~~a\nbb\ncc~~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 3, column: 5))
    }

    @Test("flag-off: a two-line single-tilde strikethrough ends on the closer's real line")
    func singleTildeSpecCorrect() throws {
        // `~a` on line 1, `b~` on line 2. Closer `~` at line 2 col 2 (b=1, ~=2), half-open @2:3.
        let range = try #require(try strikethroughRange(in: "~a\nb~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("a single-line strikethrough is unchanged either flag (opener and closer share a line)")
    func singleLineUnchanged() throws {
        // `~~a~~`: opener and closer on line 1, so the byte-projected half-open end (@1:6) already sits
        // on the opener's line and cmark's non-update of end_line is a no-op. Identical flag-off/flag-on
        // (the `strikeend-1line-ctl` control pair).
        let specRange = try #require(try strikethroughRange(in: "~~a~~", options: Self.specOptions))
        #expect(specRange.lowerBound == Pos(line: 1, column: 1))
        #expect(specRange.upperBound == Pos(line: 1, column: 6))

        let quirkRange = try #require(try strikethroughRange(in: "~~a~~", options: Self.quirkOptions))
        #expect(quirkRange == specRange)
    }

    @Test("a strikethrough ending on its own line before a soft break keeps its real range (no cross)")
    func closesBeforeSoftBreakUnchanged() throws {
        // `~~ab~~\ncd`: the strikethrough closes on line 1 (the soft break follows it), so it never
        // crosses a line and is identical flag-off/flag-on: @1:1-1:7 (the `strikeend-nocross-ctl` pair).
        let specRange = try #require(try strikethroughRange(in: "~~ab~~\ncd", options: Self.specOptions))
        #expect(specRange.lowerBound == Pos(line: 1, column: 1))
        #expect(specRange.upperBound == Pos(line: 1, column: 7))

        let quirkRange = try #require(try strikethroughRange(in: "~~ab~~\ncd", options: Self.quirkOptions))
        #expect(quirkRange == specRange)
    }

    @Test("flag-off: a strikethrough nested in emphasis crossing a line ends on the closer's real line")
    func nestedInEmphasisSpecCorrect() throws {
        // `*~~a\nb~~*`: emphasis wraps a two-line strikethrough. Fixture sanity: both nodes must form.
        let src = "*~~a\nb~~*"
        let allKinds = try kinds(in: src, options: Self.specOptions)
        #expect(allKinds.contains(.emphasis), "fixture must form an emphasis wrapper")
        // The `~~` opener is at line 1 col 2 (after `*`); the closer `~~` ends at line 2 col 4 (half-open).
        let range = try #require(try strikethroughRange(in: src, options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 4))
    }

    @Test("flag-off: a strikethrough crossing a backslash hard break ends on the closer's real line")
    func backslashHardBreakSpecCorrect() throws {
        // `~~a\<newline>b~~`: a matched strikethrough spanning a backslash hard break. Flag-off (the
        // shipped default) byte-projects the closer onto its real physical line 2, half-open @2:4.
        let range = try #require(try strikethroughRange(in: "~~a\\\nb~~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 4))
    }
}
