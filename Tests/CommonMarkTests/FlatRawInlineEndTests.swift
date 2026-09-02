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

    /// `` ` `\n `x `` : a one-backtick code span opening after a leading space on line 1 and closing after
    /// a leading space on line 2. The closing line's leading space is what distinguishes the two ends:
    /// the precise half-open end is @2:3 (one past the closing backtick's real column on line 2), while
    /// cmark's `adjust_subj_node_newlines` reports @2:2 - `since_newline` counts only the bytes cmark
    /// copied into its buffer, which excludes the stripped leading space (Quirk G extended to code spans).
    private static let leadingSpaceCodeSpanSource = " `\n `x"

    /// `` `\n`8 `` : a two-line code span (`` `\n` ``) FOLLOWED by text `8`. With sourcepos off cmark's
    /// `subj->line` never advances across the code span's interior newline, so the trailing `8` is
    /// stamped on the code span's start line (flat @1:4) instead of its physical line 2 (@2:2). This is
    /// the persistent-flat-cursor half of the quirk: the un-advanced cursor governs every LATER inline.
    private static let codeSpanFollowSource = "`\n`8"
    /// `` `\n`a`\n`b `` : two two-line code spans in a row, each swallowing one interior newline, each
    /// followed by text. The swallowed newlines ACCUMULATE, so under the flat option everything after
    /// the first code span stays on line 1: `` ` ``@1:1-1:4, `a`@1:4-1:5, `` ` ``@1:5-1:8, `b`@1:8-1:9.
    private static let twoRawSource = "`\n`a`\n`b"
    /// `` `\n`8\n9 `` : a two-line code span, text `8`, a SOFT break, then text `9`. The code span
    /// swallows one interior newline (not recorded as a logical line), so the soft break's line advance
    /// counts from the reduced base: physical `9` on line 3 is stamped @2:1 under the flat option.
    private static let codeSpanSoftBreakSource = "`\n`8\n9"

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

    private func leadingSpaceCodeSpanRange(options: MarkdownDocument.ParseOptions) throws -> Range<Pos>? {
        try firstRange(matching: { if case .codeInline = $0 { return true } else { return false } },
                       in: Self.leadingSpaceCodeSpanSource, options: options)
    }

    /// Every text node's range in DFS order, parsing `src` with `options`. Used to pin the position of
    /// the inline text FOLLOWING a raw inline (the persistent-flat-cursor half of the quirk).
    private func textRanges(in src: String, options: MarkdownDocument.ParseOptions) throws -> [Range<Pos>?] {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> [Range<Pos>?] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges.filter { $0.kind == .text }.map { $0.range }
        }
    }

    /// Every code-span node's range in DFS order.
    private func codeInlineRanges(in src: String, options: MarkdownDocument.ParseOptions) throws -> [Range<Pos>?] {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> [Range<Pos>?] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges.filter { if case .codeInline = $0.kind { return true } else { return false } }.map { $0.range }
        }
    }

    @Test("a two-line code span keeps its precise end (positions on, no flat option)")
    func codeSpanPrecise() throws {
        let range = try #require(try codeSpanRange(options: [.sourcePosition]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkBugCompatibility` alone does not flatten a no-leading-space code span's end onto its start line")
    func codeSpanNoLeadingSpaceUnderBugCompatibility() throws {
        // `` `a\nb` `` has no stripped leading whitespace, so cmark's `adjust_subj_node_newlines`
        // end (`since_newline`, content-space) coincides with the precise half-open end @2:3. The
        // divergence only appears when the closing line has leading whitespace cmark strips (see
        // `codeSpanLeadingSpaceQuirkUnderBugCompatibility`). Either way the end is NOT the flat
        // sourcepos-OFF @1:6 (`.cmarkFlatRawInlineEnds`, below).
        let range = try #require(try codeSpanRange(options: [.sourcePosition, .cmarkBugCompatibility]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("a two-line leading-space code span keeps its precise end (positions on, no flat option)")
    func codeSpanLeadingSpacePrecise() throws {
        // Spec-correct default (deliverable): the code span's end is one past its closing backtick's
        // real column on line 2. The closing line ` `x` puts the backtick at column 2, so the
        // half-open end is @2:3. This is the guardrail that the shipped default is unaffected by the
        // bug-compat quirk below.
        let range = try #require(try leadingSpaceCodeSpanRange(options: [.sourcePosition]))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkBugCompatibility` gives a leading-space code span cmark's since_newline end")
    func codeSpanLeadingSpaceQuirkUnderBugCompatibility() throws {
        // Quirk G extended to code spans: cmark's `adjust_subj_node_newlines` sets `end_column =
        // since_newline`, a count of the bytes cmark copied into its buffer since the last interior
        // newline. That buffer excludes the stripped leading space of line 2 ` `x`, so the end lands
        // at @2:2 (the closing backtick's column), one short of the precise half-open @2:3 above. The
        // column comes from content-space arithmetic, not the physical source column (which would
        // re-include the stripped space and overshoot to @2:3).
        let range = try #require(try leadingSpaceCodeSpanRange(options: [.sourcePosition, .cmarkBugCompatibility]))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 2))
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

    // MARK: - Persistent flat cursor: the text FOLLOWING a newline-crossing raw inline

    @Test("text after a two-line code span keeps its physical position (positions on, no flat option)")
    func followingTextPreciseNoQuirk() throws {
        let texts = try textRanges(in: Self.codeSpanFollowSource, options: [.sourcePosition])
        let range = try #require(texts.first ?? nil, "fixture must have a text node after the code span")
        #expect(texts.count == 1)  // fixture sanity: exactly the trailing `8`
        // Physical: `8` is on line 2 (` `8`), one past the closing backtick at column 1.
        #expect(range.lowerBound == Pos(line: 2, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkBugCompatibility` alone does NOT flatten the following text (Quirk G regime is physical)")
    func followingTextPhysicalUnderBugCompatibility() throws {
        // Without `disableSourcePosOpts` cmark leaves `CMARK_OPT_SOURCEPOS` on, so its cursor resets at
        // the code span's interior newline like every other construct: the trailing `8` stays physical
        // at @2:2. The flat behavior is gated on `.cmarkFlatRawInlineEnds`, not `.cmarkBugCompatibility`.
        let texts = try textRanges(in: Self.codeSpanFollowSource, options: [.sourcePosition, .cmarkBugCompatibility])
        let range = try #require(texts.first ?? nil)
        #expect(range.lowerBound == Pos(line: 2, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkFlatRawInlineEnds` stamps the following text from the un-advanced flat cursor")
    func followingTextFlatUnderFlatOption() throws {
        let texts = try textRanges(in: Self.codeSpanFollowSource, options: [.sourcePosition, .cmarkFlatRawInlineEnds])
        let range = try #require(texts.first ?? nil)
        // Flat: the code span's interior newline never advanced the cursor, so `8` follows the code
        // span's flat end (@1:4) on line 1, not its physical line 2.
        #expect(range.lowerBound == Pos(line: 1, column: 4))
        #expect(range.upperBound == Pos(line: 1, column: 5))
    }

    @Test("two newline-crossing code spans accumulate their swallowed-newline offset")
    func twoRawInlinesAccumulate() throws {
        // Control (no flat option): both trailing texts stay on their physical lines 2 and 3.
        let physicalTexts = try textRanges(in: Self.twoRawSource, options: [.sourcePosition])
        #expect(physicalTexts.count == 2)  // fixture sanity: `a` and `b`
        #expect(try #require(physicalTexts.first ?? nil).lowerBound == Pos(line: 2, column: 2))
        #expect(try #require(physicalTexts.last ?? nil).lowerBound == Pos(line: 3, column: 2))

        // Flat: the first code span swallows a newline, so the SECOND code span and both texts stay on
        // line 1, its own flat end continuing from the reduced base (@1:5-1:8, not a physical line 2/3).
        let codeSpans = try codeInlineRanges(in: Self.twoRawSource, options: [.sourcePosition, .cmarkFlatRawInlineEnds])
        #expect(codeSpans.count == 2)  // fixture sanity: two code spans
        let secondSpan = try #require(codeSpans.last ?? nil)
        #expect(secondSpan.lowerBound == Pos(line: 1, column: 5))
        #expect(secondSpan.upperBound == Pos(line: 1, column: 8))

        let flatTexts = try textRanges(in: Self.twoRawSource, options: [.sourcePosition, .cmarkFlatRawInlineEnds])
        #expect(try #require(flatTexts.first ?? nil).lowerBound == Pos(line: 1, column: 4))  // `a`
        #expect(try #require(flatTexts.last ?? nil).lowerBound == Pos(line: 1, column: 8))   // `b`
    }

    @Test("a soft break after a newline-crossing code span advances the line from the reduced base")
    func softBreakAdvancesFromFlatBase() throws {
        // Control (no flat option): the trailing `9` is on its physical line 3.
        let physicalTexts = try textRanges(in: Self.codeSpanSoftBreakSource, options: [.sourcePosition])
        #expect(physicalTexts.count == 2)  // fixture sanity: `8` and `9`
        #expect(try #require(physicalTexts.last ?? nil).lowerBound == Pos(line: 3, column: 1))

        // Flat: the code span swallowed one interior newline that was never recorded as a logical line,
        // so the soft break advances to line 2 (not 3) and stamps `9` @2:1 - the offset persists through
        // the soft-break line advance.
        let flatTexts = try textRanges(in: Self.codeSpanSoftBreakSource, options: [.sourcePosition, .cmarkFlatRawInlineEnds])
        #expect(try #require(flatTexts.first ?? nil).lowerBound == Pos(line: 1, column: 4))  // `8`
        let ninth = try #require(flatTexts.last ?? nil)  // `9`
        #expect(ninth.lowerBound == Pos(line: 2, column: 1))
        #expect(ninth.upperBound == Pos(line: 2, column: 2))
    }
}
