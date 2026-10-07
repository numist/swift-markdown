/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges of raw HTML that spans a line ending, such as `<foo\nbar>`. The end is half-open, one column past the
/// closing `>`, as for every other node.
@Suite("Multi-line inline HTML source ranges")
struct InlineHTMLMultilineEndTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    /// The source range of the first raw HTML node in `src`.
    private func inlineHTMLRange(in src: String) -> Range<Pos>? {
        MarkdownDocument.withParsedDocument(src, options: Self.options) {
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
        let range = try #require(inlineHTMLRange(in: "<foo\nbar>"))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 5))
    }

    @Test("a mid-text two-line inline HTML span keeps the half-open end")
    func midTextTwoLineSpanHalfOpen() throws {
        let range = try #require(inlineHTMLRange(in: "x<a\nb>y"))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("a single-line inline HTML span keeps the half-open end")
    func singleLineSpanHalfOpen() throws {
        let range = try #require(inlineHTMLRange(in: "a <foo> b"))
        #expect(range.lowerBound == Pos(line: 1, column: 3))
        #expect(range.upperBound == Pos(line: 1, column: 8))
    }
}
