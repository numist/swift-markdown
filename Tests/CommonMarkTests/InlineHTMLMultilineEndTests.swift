/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for a raw inline-HTML span whose token crosses a newline (the angle-bracket form
/// can't span a newline, so `<foo\nbar>` parses as `InlineHTML`, not an autolink).
///
/// cmark-gfm reports such a span's END COLUMN one short: its `adjust_subj_node_newlines`
/// (`src/inlines.c` ~304) overwrites the node's `end_column` with a raw byte count since the last
/// interior newline, skipping the `+ 1 + column_offset + block_offset` that `make_literal` applies
/// to a single-line node's end column - so the end lands on the last byte's own column (the closing
/// `>`), not the half-open (last-byte + 1). That flat end is the `.cmarkBugCompatibility` quirk,
/// covered by the `htmlml-*` fuzzer regression pairs (which parse flag-on). This suite is the
/// flag-off guardrail proving the default (shipped, spec-correct) parser reports the ordinary
/// half-open end that every single-line node uses. A single-line span carries no interior newline
/// and is unchanged either way.
@Suite("Multi-line inline HTML source ranges (spec-correct)")
struct InlineHTMLMultilineEndTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Source positions on, cmark bug-compatibility deliberately OFF (the shipped default).
    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    /// The source range of the first `.htmlInline` node when `src` is parsed spec-correct.
    private func inlineHTMLRange(in src: String) throws -> Range<Pos>? {
        try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> Range<Pos>? in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            for entry in ranges where entry.kind == .htmlInline {
                return entry.range
            }
            return nil
        }
    }

    @Test("a two-line inline HTML span keeps the half-open end")
    func twoLineSpanHalfOpen() throws {
        // `<foo` on line 1 (the `<` at col 1), `bar>` on line 2. Spec-correct, the end is half-open:
        // the closing `>` is at line 2 col 4 (b=1, a=2, r=3, >=4), so the end is one past it, @2:5.
        // cmark's quirk reports the `>`'s own column, @1:1-2:4 (the `htmlml-basic` fuzzer pair, flag-on).
        let range = try #require(try inlineHTMLRange(in: "<foo\nbar>"))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 5))
    }

    @Test("a mid-text two-line inline HTML span keeps the half-open end")
    func midTextTwoLineSpanHalfOpen() throws {
        // `x<a` on line 1 (the `<` at col 2), `b>y` on line 2. Spec-correct, the closing `>` is at
        // line 2 col 2 (b=1, >=2), so the half-open end is one past it, @2:3. cmark's quirk reports
        // the `>`'s own column, @1:2-2:2 (the `htmlml-midtext` fuzzer pair, flag-on).
        let range = try #require(try inlineHTMLRange(in: "x<a\nb>y"))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("a single-line inline HTML span is unchanged (half-open, no interior newline)")
    func singleLineSpanUnchanged() throws {
        // `a <foo> b`: the span carries no interior newline, so cmark's newline adjustment never
        // fires and the end is the ordinary half-open column both flag-off and flag-on. The `<` is at
        // col 3, the `>` at col 7, so the half-open end is @1:8 (the `htmlml-sl-ctl` control pair).
        let range = try #require(try inlineHTMLRange(in: "a <foo> b"))
        #expect(range.lowerBound == Pos(line: 1, column: 3))
        #expect(range.upperBound == Pos(line: 1, column: 8))
    }
}
