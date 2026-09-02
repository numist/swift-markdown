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
/// The deliverable stamps the precise byte-projected end: one past the token's last content byte on
/// its own physical line. These guardrails pin that end and confirm `.cmarkBugCompatibility` does not
/// disturb it.
@Suite("Flat raw-inline (code span / inline HTML) end ranges")
struct FlatRawInlineEndTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// `` `a\nb` `` : a code span spanning two lines. Precise end @2:3 (its closing backtick's line).
    private static let codeSpanSource = "`a\nb`"

    /// `` ` `\n `x `` : a one-backtick code span opening after a leading space on line 1 and closing after
    /// a leading space on line 2. Precise half-open end @2:3 (one past the closing backtick on line 2).
    private static let leadingSpaceCodeSpanSource = " `\n `x"

    /// `` `\n`8 `` : a two-line code span (`` `\n` ``) FOLLOWED by text `8`. The trailing `8` is stamped
    /// on its physical line 2 (@2:2).
    private static let codeSpanFollowSource = "`\n`8"

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

    private func leadingSpaceCodeSpanRange(options: MarkdownDocument.ParseOptions) throws -> Range<Pos>? {
        try firstRange(matching: { if case .codeInline = $0 { return true } else { return false } },
                       in: Self.leadingSpaceCodeSpanSource, options: options)
    }

    /// Every text node's range in DFS order, parsing `src` with `options`.
    private func textRanges(in src: String, options: MarkdownDocument.ParseOptions) throws -> [Range<Pos>?] {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> [Range<Pos>?] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges.filter { $0.kind == .text }.map { $0.range }
        }
    }

    @Test("a two-line code span keeps its precise end (positions on)")
    func codeSpanPrecise() throws {
        let range = try #require(try codeSpanRange(options: [.sourcePosition]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkBugCompatibility` does not disturb a two-line code span's precise end")
    func codeSpanNoLeadingSpaceUnderBugCompatibility() throws {
        let range = try #require(try codeSpanRange(options: [.sourcePosition, .cmarkBugCompatibility]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("a two-line leading-space code span keeps its precise end (positions on)")
    func codeSpanLeadingSpacePrecise() throws {
        // The code span's end is one past its closing backtick's real column on line 2. The closing
        // line ` `x` puts the backtick at column 2, so the half-open end is @2:3.
        let range = try #require(try leadingSpaceCodeSpanRange(options: [.sourcePosition]))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    // MARK: - The text FOLLOWING a newline-crossing raw inline

    @Test("text after a two-line code span keeps its physical position (positions on)")
    func followingTextPreciseNoQuirk() throws {
        let texts = try textRanges(in: Self.codeSpanFollowSource, options: [.sourcePosition])
        let range = try #require(texts.first ?? nil, "fixture must have a text node after the code span")
        #expect(texts.count == 1)  // fixture sanity: exactly the trailing `8`
        // Physical: `8` is on line 2 (` `8`), one past the closing backtick at column 1.
        #expect(range.lowerBound == Pos(line: 2, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("`.cmarkBugCompatibility` does not disturb the following text's physical position")
    func followingTextPhysicalUnderBugCompatibility() throws {
        let texts = try textRanges(in: Self.codeSpanFollowSource, options: [.sourcePosition, .cmarkBugCompatibility])
        let range = try #require(texts.first ?? nil)
        #expect(range.lowerBound == Pos(line: 2, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }
}
