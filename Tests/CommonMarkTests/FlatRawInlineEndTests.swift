/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for the END of the two raw-scan inlines (code spans, inline HTML) whose token
/// crosses a newline.
///
/// With `CMARK_OPT_SOURCEPOS` off the old C path flattened these two constructs' `end_column` onto
/// their start line (`(startLine, startColumn + tokenByteLength)`), ignoring the interior break. The
/// rewrite reproduces that flat end ONLY under `.cmarkFlatRawInlineEnds` (forwarded by the Markdown
/// layer for the differential's flag-on + `disableSourcePosOpts` combination). This suite is the
/// parser-layer guardrail: it proves the flat end is gated on `.cmarkFlatRawInlineEnds` specifically,
/// staying precise even with `.cmarkBugCompatibility` on, and it pins the flat end the new option
/// produces. The end-to-end surface is covered by the `rawinline-*` fuzzer regression pairs.
@Suite("Flat raw-inline (code span / inline HTML) end ranges")
struct FlatRawInlineEndTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// `` `a\nb` `` : a code span spanning two lines. Precise end @2:3 (its closing backtick's line);
    /// cmark's sourcepos-off flat end is @1:6 (start column 1 + the 5-byte token).
    private static let codeSpanSource = "`a\nb`"
    /// `<foo\nbar>` : inline HTML spanning two lines. Precise half-open end @2:5 (one past the closing
    /// `>` on line 2); cmark's sourcepos-off flat end is @1:10 (start column 1 + the 9-byte token).
    private static let inlineHTMLSource = "<foo\nbar>"

    /// The source range of the first node whose kind satisfies `match`, parsing `src` with `options`.
    private func firstRange(
        matching match: @escaping (MarkdownNode.Kind) -> Bool,
        in src: String,
        options: MarkdownDocument.ParseOptions
    ) throws -> Range<Pos>? {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> Range<Pos>? in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            for entry in ranges where match(entry.kind) {
                return entry.range
            }
            return nil
        }
    }

    private func codeSpanRange(options: MarkdownDocument.ParseOptions) throws -> Range<Pos>? {
        try firstRange(matching: { if case .codeInline = $0 { return true } else { return false } },
                       in: Self.codeSpanSource, options: options)
    }

    private func inlineHTMLRange(options: MarkdownDocument.ParseOptions) throws -> Range<Pos>? {
        try firstRange(matching: { $0 == .htmlInline }, in: Self.inlineHTMLSource, options: options)
    }

    @Test("a two-line code span keeps its precise end (positions on, no flat option)")
    func codeSpanPrecise() throws {
        let range = try #require(try codeSpanRange(options: [.sourcePosition]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkBugCompatibility` alone does not flatten a code span's end")
    func codeSpanPreciseUnderBugCompatibility() throws {
        let range = try #require(try codeSpanRange(options: [.sourcePosition, .cmarkBugCompatibility]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkBugCompatibility` alone gives inline HTML Quirk G's end, not the flat raw-inline end")
    func inlineHTMLQuirkGUnderBugCompatibility() throws {
        // Under `.cmarkBugCompatibility` (but no flat option) a newline-crossing inline HTML span takes
        // Quirk G's sourcepos-ON end: the closing `>`'s own column @2:4 (see `stampInlineHTMLEnd`).
        // That is distinct from both the precise half-open @2:5 (no bug-compat, `InlineHTMLMultilineEndTests`)
        // and the sourcepos-OFF flat @1:10 (`.cmarkFlatRawInlineEnds`, below), so the flat option is a
        // separate, overriding trigger.
        let range = try #require(try inlineHTMLRange(options: [.sourcePosition, .cmarkBugCompatibility]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 4))
    }

    @Test("`.cmarkFlatRawInlineEnds` flattens a code span's end onto its start line")
    func codeSpanFlat() throws {
        let range = try #require(try codeSpanRange(options: [.sourcePosition, .cmarkFlatRawInlineEnds]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 1, column: 6))
    }

    @Test("`.cmarkFlatRawInlineEnds` flattens an inline HTML span's end onto its start line")
    func inlineHTMLFlat() throws {
        let range = try #require(try inlineHTMLRange(options: [.sourcePosition, .cmarkFlatRawInlineEnds]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 1, column: 10))
    }
}
