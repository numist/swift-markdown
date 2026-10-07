/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A `~` or `~~` run that closes no strikethrough is literal text (Strikethrough (extension)), and its
/// source range covers its bytes like any other text.
@Suite("Unmatched strikethrough source ranges")
struct UnmatchedStrikethroughRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let options: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The source range of the first text node, in DFS order.
    private func firstTextRange(in src: String) -> Range<Pos>? {
        let ranges = MarkdownDocument.withParsedDocument(src, options: Self.options) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.first { $0.kind == .text }?.range
    }

    @Test("standalone unmatched ~ has a range covering it")
    func standaloneSingleTilde() {
        let range = firstTextRange(in: "~")
        #expect(range?.lowerBound == Pos(line: 1, column: 1))
        #expect(range?.upperBound == Pos(line: 1, column: 2))
    }

    @Test("standalone unmatched ~~ has a range covering it")
    func standaloneDoubleTilde() {
        let range = firstTextRange(in: "~~")
        #expect(range?.lowerBound == Pos(line: 1, column: 1))
        #expect(range?.upperBound == Pos(line: 1, column: 3))
    }

    @Test("trailing unmatched ~ merges into the preceding text run")
    func trailingTilde() {
        let range = firstTextRange(in: "a~")
        #expect(range?.lowerBound == Pos(line: 1, column: 1))
        #expect(range?.upperBound == Pos(line: 1, column: 3))
    }
}
