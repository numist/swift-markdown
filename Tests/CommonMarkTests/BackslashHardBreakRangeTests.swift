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
/// from the break's line. The shipped (flag-off, spec-correct) parser instead projects each node onto
/// its true physical line:column, so the next line's content resets to that line - exactly like a
/// soft break. cmark's non-resetting flat columns are the `.cmarkBugCompatibility` quirk, covered by
/// the `bshb-*` / `sab-*` fuzzer regression pairs (which parse flag-on); this suite is the flag-off
/// guardrail proving the default parser is spec-correct.
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
        // keeps counting flat from line 1 and reports @1:6-1:9 (the `bshb-simple` fuzzer pair, flag-on).
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
        // physical line; cmark flattens all three onto line 1 (`bshb-multiple`: @1:1, @1:4, @1:7).
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
        // `a\` line 1, a lone `~` line 2. Flag-off the `~` is ordinary literal text (the strikethrough
        // zero-width quirk emits only flag-on), so it gets a normal width-bearing range on its own
        // physical line @2:1-2:2. cmark flattens it and, via strikethrough.c's unset end column,
        // reports no position (the `sab-strike-standalone` fuzzer pair, flag-on).
        let texts = try textRanges(in: "a\\\n~")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // "a"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 2))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "~"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
    }
}
