/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for the inline content that REMAINS after leading link reference definitions are
/// stripped off the front of a paragraph.
///
/// The shipped (flag-off, spec-correct) parser reports the surviving content at its TRUE physical
/// position: a paragraph whose first N lines are reference definitions still stamps the remaining
/// text on the physical line it actually occupies. cmark-gfm instead extracts the ref-defs by
/// dropping their bytes off the front of the paragraph's content buffer and then inline-parses the
/// remainder with the subject based at the paragraph's ORIGINAL start line, so the surviving content
/// is stamped N lines too HIGH (column preserved) - an internally inconsistent tree where the text
/// node's line sits above its own paragraph's start line. That is cmark's bug: it is the
/// `.cmarkBugCompatibility` quirk, covered flag-on by the `refdef-*` fuzzer regression pairs. This
/// suite is the flag-off guardrail proving the default parser keeps the true positions.
@Suite("Reference-definition remainder source ranges (spec-correct)")
struct ReferenceDefinitionRemainderRangeTests {

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

    @Test("content after a one-line ref-def keeps its true line, not the paragraph's start line")
    func singleLineRefDef() throws {
        // "[foo]: /url" on line 1 is a reference definition; "bar" on line 2 is the surviving content.
        // Spec-correct, `bar` keeps its TRUE line: @2:1-2:4 - the physical line it occupies, consistent
        // with the paragraph end @2:4. cmark strips the def and stamps `bar` one line up at @1:1-1:4
        // (the `refdef-then-para` fuzzer pair, flag-on). The block-level paragraph range is @1:1-2:4 in
        // both configurations - only the inline content shifts.
        let ranges = try ranges(in: "[foo]: /url\nbar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 1)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 2, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 2, column: 1))   // "bar" on its true line
        #expect(texts[0]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("content after a multi-line-label ref-def keeps its true line")
    func multiLineLabelRefDef() throws {
        // The reference definition "[\nfoo\n]: /url" spans lines 1-3 (its label runs across two
        // newlines); "bar" on line 4 is the surviving content. Spec-correct, `bar` keeps its TRUE line
        // @4:1-4:4, consistent with the paragraph end @4:4. cmark drops all three ref-def lines from
        // the buffer and stamps `bar` three lines up at @1:1-1:4 (the `refdef-mlabel` fuzzer pair,
        // flag-on) - a text line (1) that sits at the paragraph's own start line. Block-level paragraph
        // range is @1:1-4:4 in both configurations.
        let ranges = try ranges(in: "[\nfoo\n]: /url\nbar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 1)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 4, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 4, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 4, column: 1))   // "bar" on its true line
        #expect(texts[0]?.upperBound == Pos(line: 4, column: 4))
    }

    @Test("every remaining line keeps its own true line after a ref-def")
    func multipleRemainingLines() throws {
        // "[foo]: /url" on line 1 is the ref-def; "bar" (line 2) and "baz" (line 3) both survive.
        // Spec-correct, each keeps its TRUE line: `bar` @2:1-2:4, `baz` @3:1-3:4 - consistent with the
        // paragraph end @3:4. cmark shifts BOTH up one line (`bar` @1:1, `baz` @2:1 - the
        // `refdef-then-2line` fuzzer pair, flag-on), proving the shift is per-line, not a constant byte
        // offset. Block-level paragraph range is @1:1-3:4 in both configurations.
        let ranges = try ranges(in: "[foo]: /url\nbar\nbaz")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 2)

        #expect(firstRange(.document, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.document, in: ranges)?.upperBound == Pos(line: 3, column: 4))
        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 3, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 2, column: 1))   // "bar" on its true line
        #expect(texts[0]?.upperBound == Pos(line: 2, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 3, column: 1))   // "baz" on its true line
        #expect(texts[1]?.upperBound == Pos(line: 3, column: 4))
    }

    @Test("nested inline content after a ref-def keeps its true line, whole subtree")
    func nestedInlineRemainder() throws {
        // "[foo]: /url" (line 1) is the ref-def; "a *b* c" (line 2) is the surviving content, which
        // parses to Text "a ", an Emphasis wrapping Text "b", and Text " c". Spec-correct, EVERY node
        // of that subtree keeps its TRUE line 2, consistent with the paragraph end @2:8. cmark shifts
        // the whole subtree up one line - Text @1:1, Emphasis @1:3, inner Text @1:4, Text @1:6 (the
        // `refdef-then-emph` fuzzer pair, flag-on) - proving the shift applies to non-text inlines and
        // through nesting, not just top-level text. Block-level paragraph range is @1:1-2:8 both ways.
        let ranges = try ranges(in: "[foo]: /url\na *b* c")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 3)

        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 1, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 2, column: 8))

        #expect(texts[0]?.lowerBound == Pos(line: 2, column: 1))   // "a " on its true line
        #expect(texts[0]?.upperBound == Pos(line: 2, column: 3))
        #expect(firstRange(.emphasis, in: ranges)?.lowerBound == Pos(line: 2, column: 3))   // "*b*"
        #expect(firstRange(.emphasis, in: ranges)?.upperBound == Pos(line: 2, column: 6))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 4))   // inner "b"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 5))
        #expect(texts[2]?.lowerBound == Pos(line: 2, column: 6))   // " c"
        #expect(texts[2]?.upperBound == Pos(line: 2, column: 8))
    }

    @Test("a blank line between ref-def and content is a separate paragraph - no shift")
    func blankSeparatorIsSeparateParagraph() throws {
        // "[foo]: /url" (line 1), a blank line (line 2), then "bar" (line 3). The blank line ends the
        // former ref-def paragraph, so `bar` is its OWN paragraph with no leading def to strip - there
        // is nothing to shift. Both configurations report `bar` @3:1-3:4 (the `refdef-blank-ctl` fuzzer
        // control, EQUAL flag-on). This proves the shift is scoped to content that shares a paragraph
        // with the stripped defs.
        let ranges = try ranges(in: "[foo]: /url\n\nbar")
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 1)

        #expect(firstRange(.paragraph, in: ranges)?.lowerBound == Pos(line: 3, column: 1))
        #expect(firstRange(.paragraph, in: ranges)?.upperBound == Pos(line: 3, column: 4))

        #expect(texts[0]?.lowerBound == Pos(line: 3, column: 1))   // "bar" on its true line
        #expect(texts[0]?.upperBound == Pos(line: 3, column: 4))
    }
}
