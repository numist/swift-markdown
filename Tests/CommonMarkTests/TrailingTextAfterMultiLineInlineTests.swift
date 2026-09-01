/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Coverage for source-position stamping of a plain-text run that FOLLOWS a multi-line inline (code span
/// or emphasis) on the last content line of a **re-indented multi-segment** paragraph - a blockquote or
/// list-item paragraph whose lazy continuations are joined as a segment list.
///
/// The multi-line inline consumes the segment's first physical line, so the trailing text run STARTS on a
/// later physical line than its segment's re-indent base (`sourceRunBase`, which sits on the segment's
/// FIRST line). Under `.cmarkBugCompatibility` the re-indent (Quirk E, `BlockParser.addLineSegment`) shifts
/// the run's mapped source offsets to the block content column, so the run's START byte projects PAST its
/// own physical line onto the next one. The overshoot correction in `InlineParser.stampInline` must anchor
/// the run's START on its own physical line (not leave it byte-projected onto the later line), or the node
/// gets an inverted range that renders with no `@line:col`. (Complementary to `MultiLineSegmentRangeTests`,
/// whose runs start on their own line - here a preceding multi-line inline pushes the start past it.
/// Regression for the differential-fuzzer `txtaftml-*` pairs.)
@Suite("Trailing text after a multi-line inline in a re-indented container paragraph")
struct TrailingTextAfterMultiLineInlineTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]
    private static let quirkOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]

    private func textRanges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> [Range<Pos>?] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out.filter { $0.kind == .text }.map(\.range)
    }

    /// The deliverable (flag-OFF, spec-correct default): the trailing `o` after a multi-line code span in a
    /// blockquote paragraph carries its true byte-projected position on its own physical line (`@2:2-2:3`).
    @Test("flag-OFF: text after a multi-line code span is stamped on its own line")
    func specTrailingTextStamped() throws {
        let texts = try textRanges("> `\n`o\nx", options: Self.specOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 2, column: 2)..<Pos(line: 2, column: 3))   // "o"
        #expect(texts[1] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "x"
    }

    /// Flag-ON (differential-fuzzer configuration). cmark counts the re-indented continuation's columns flat
    /// from the block content column, so the trailing `o` reports `@2:4-2:5` (not its physical `@2:2`), and
    /// crucially keeps its own line - the overshoot must not leave it position-less.
    @Test("flag-ON: text after a multi-line code span in a blockquote keeps its own line")
    func quirkTrailingTextBlockQuote() throws {
        let texts = try textRanges("> `\n`o\nx", options: Self.quirkOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 2, column: 4)..<Pos(line: 2, column: 5))   // "o"
        #expect(texts[1] == Pos(line: 3, column: 3)..<Pos(line: 3, column: 4))   // "x"
    }

    /// Flag-ON: the same with a list-item paragraph (also a re-indented multi-segment container).
    @Test("flag-ON: text after a multi-line code span in a list item keeps its own line")
    func quirkTrailingTextListItem() throws {
        let texts = try textRanges("- `\n`o\nx", options: Self.quirkOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 2, column: 4)..<Pos(line: 2, column: 5))   // "o"
        #expect(texts[1] == Pos(line: 3, column: 3)..<Pos(line: 3, column: 4))   // "x"
    }

    /// Flag-ON: the trailing text follows a multi-line EMPHASIS (`*a\nb*`) rather than a code span. The
    /// `o` starts right after the closer on line 2 and reports `@2:5-2:6`.
    @Test("flag-ON: text after a multi-line emphasis in a blockquote keeps its own line")
    func quirkTrailingTextAfterEmphasis() throws {
        let texts = try textRanges("> *a\nb*o\nx", options: Self.quirkOptions)
        try #require(texts.count == 4)
        #expect(texts[0] == Pos(line: 1, column: 4)..<Pos(line: 1, column: 5))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 3)..<Pos(line: 2, column: 4))   // "b"
        #expect(texts[2] == Pos(line: 2, column: 5)..<Pos(line: 2, column: 6))   // "o"
        #expect(texts[3] == Pos(line: 3, column: 3)..<Pos(line: 3, column: 4))   // "x"
    }
}
