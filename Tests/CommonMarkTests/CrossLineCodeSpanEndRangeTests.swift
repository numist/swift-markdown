/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A code span that crosses a line ending ends just past its closing backtick string, on the line that
/// holds it.
@Suite("Code span across a line ending: end of source range")
struct CrossLineCodeSpanEndRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let codeSpanSource = "`a\nb`"

    private static let leadingSpaceCodeSpanSource = " `\n `x"

    private static let codeSpanFollowSource = "`\n`8"

    /// The source range of the first node whose kind satisfies `match`, parsing `src` with `options`.
    private func firstRange(
        matching match: @escaping (MarkdownNode.Kind) -> Bool,
        in src: String,
        options: MarkdownDocument.ParseOptions
    ) -> Range<Pos>? {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> Range<Pos>? in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            for entry in ranges where match(entry.kind) {
                return entry.range
            }
            return nil
        }
    }

    private func codeSpanRange(options: MarkdownDocument.ParseOptions) -> Range<Pos>? {
        firstRange(matching: { if case .codeInline = $0 { return true } else { return false } },
                       in: Self.codeSpanSource, options: options)
    }

    private func leadingSpaceCodeSpanRange(options: MarkdownDocument.ParseOptions) -> Range<Pos>? {
        firstRange(matching: { if case .codeInline = $0 { return true } else { return false } },
                       in: Self.leadingSpaceCodeSpanSource, options: options)
    }

    /// Every text node's source range in depth-first order, parsing `src` with `options`.
    private func textRanges(in src: String, options: MarkdownDocument.ParseOptions) -> [Range<Pos>?] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> [Range<Pos>?] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges.filter { $0.kind == .text }.map { $0.range }
        }
    }

    @Test("a two-line code span ends after its closing backtick")
    func codeSpanPrecise() throws {
        let range = try #require(codeSpanRange(options: [.sourcePosition]))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("a two-line code span closed after leading whitespace ends after its closing backtick")
    func codeSpanLeadingSpacePrecise() throws {
        let range = try #require(leadingSpaceCodeSpanRange(options: [.sourcePosition]))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    // MARK: - Text after the code span

    @Test("text after a two-line code span starts on the closing line")
    func followingTextOnClosingLine() throws {
        let texts = textRanges(in: Self.codeSpanFollowSource, options: [.sourcePosition])
        let range = try #require(texts.first ?? nil, "fixture must have a text node after the code span")
        #expect(texts.count == 1)  // fixture sanity: exactly the trailing `8`
        #expect(range.lowerBound == Pos(line: 2, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }
}
