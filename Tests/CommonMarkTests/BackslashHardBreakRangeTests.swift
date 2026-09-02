/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for inline nodes that follow a *backslash hard break* - a `\` at end of line.
///
/// cmark-gfm's inline cursor does not reset across a backslash hard break: its `handle_backslash`
/// makes the LINEBREAK without touching `subj->line` / `subj->column_offset`, unlike `handle_newline`
/// for soft and trailing-space breaks. So every node after such a break keeps counting columns flat
/// from the break's line. The parser instead projects each node onto its true physical line:column,
/// so the next line's content resets to that line - exactly like a soft break, the spec-correct
/// behavior. The rewrite does not reproduce cmark's non-resetting flat columns.
@Suite("Backslash hard break source ranges (spec-correct)")
struct BackslashHardBreakRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The source ranges of every text node, in DFS order, when `src` is parsed spec-correct.
    private func textRanges(in src: String) throws -> [Range<Pos>?] {
        let ranges = try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.filter { $0.kind == .text }.map { $0.range }
    }

    @Test("text after a backslash hard break resets to the next physical line")
    func textAfterBreakResetsToNextLine() throws {
        // `foo\` on line 1 (the `\` is the hard break), `bar` on line 2. Spec-correct, `bar` resets to
        // its own physical position @2:1-2:4 (b=1, a=2, r=3, half-open end one past r). cmark's quirk
        // keeps counting flat from line 1 and reports @1:6-1:9.
        let texts = try textRanges(in: "foo\\\nbar")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "bar"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("each backslash hard break resets the following line independently")
    func multipleBreaksEachReset() throws {
        // `a\` line 1, `b\` line 2, `c` line 3. Spec-correct, each text resets to column 1 of its own
        // physical line; cmark flattens all three onto line 1 (@1:1, @1:4, @1:7).
        let texts = try textRanges(in: "a\\\nb\\\nc")
        try #require(texts.count == 3)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "a"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 2))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "b"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
        #expect(texts[2]?.lowerBound == Pos(line: 3, column: 1))   // "c"
        #expect(texts[2]?.upperBound == Pos(line: 3, column: 2))
    }

    @Test("unmatched ~ after a backslash break is width-bearing text on its own line")
    func unmatchedTildeAfterBreak() throws {
        // `a\` line 1, a lone `~` line 2. The `~` is ordinary literal text, so it gets a normal
        // width-bearing range on its own physical line @2:1-2:2. cmark flattens it and, via
        // strikethrough.c's unset end column, reports no position.
        let texts = try textRanges(in: "a\\\n~")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "a"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 2))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "~"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
    }

    // MARK: - Multi-segment continuations (a backslash-break continuation line with a stripped
    // prefix/indent makes the paragraph multi-segment). Each continuation line still resets to its
    // own TRUE physical column - the stripped whitespace shifts the column, unlike cmark's flat
    // cursor, which is indent-independent.

    @Test("text after a backslash break on a space-indented continuation resets to its true column")
    func textAfterBreakOnIndentedContinuation() throws {
        // `foo\` line 1, ` bar` line 2 (one leading space stripped from the paragraph content, making
        // it multi-segment). Spec-correct, `bar` resets to its true physical position: line 2 starts
        // at the space, so `b`=col 2, `a`=3, `r`=4, half-open end one past r = col 5. cmark's quirk
        // keeps counting flat from line 1 and reports @1:6-1:9.
        let texts = try textRanges(in: "foo\\\n bar")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 2))   // "bar"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 5))
    }

    @Test("a wider continuation indent shifts the true column flag-off")
    func textAfterBreakOnWiderIndent() throws {
        // Same as above but five leading spaces. Spec-correct, `bar`'s true column tracks the indent:
        // line 2 starts at the first space, so `b`=col 6, half-open end = col 9. cmark's flat cursor is
        // indent-independent and reports @1:6-1:9 regardless of the indent width; here the spec-correct
        // columns differ.
        let texts = try textRanges(in: "foo\\\n     bar")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "foo"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 6))   // "bar"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 9))
    }

    @Test("text after a backslash break inside a blockquote resets to its true column")
    func textAfterBreakInBlockquote() throws {
        // `> a\` line 1, `> b` line 2. The `> ` prefix is stripped from each line, so the paragraph
        // content is multi-segment. Spec-correct, both texts sit at their true content column (3, after
        // `> `): `a` @1:3-1:4 and `b` @2:3-2:4. cmark's quirk keeps counting flat across the break and
        // reports `b` @1:6-1:7, NOT counting the stripped `> ` prefix.
        let texts = try textRanges(in: "> a\\\n> b")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "a"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 3))   // "b"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("text after a backslash break on a lazy list continuation resets to its true column")
    func textAfterBreakOnLazyListContinuation() throws {
        // `- b` line 1 (list content column 3), ` \` line 2 (one leading space, below the item's
        // two-space content indent, so a LAZY continuation whose residual space cmark preserves in its
        // paragraph buffer), `c` line 3. Spec-correct, `c` resets to its own true physical position
        // @3:1-3:2. cmark's quirk keeps counting flat across the break AND, because the residual space
        // survives in its buffer, reports `c` one column past the residual-free position: @2:6-2:7. A
        // two-space continuation is instead a MATCHED continuation whose residual is discarded, so its
        // flat column has no such shift (@2:5-2:6).
        let texts = try textRanges(in: "- b\n \\\nc")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 3))   // "b"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 4))
        #expect(texts[1]?.lowerBound == Pos(line: 3, column: 1))   // "c"
        #expect(texts[1]?.upperBound == Pos(line: 3, column: 2))
    }
}
