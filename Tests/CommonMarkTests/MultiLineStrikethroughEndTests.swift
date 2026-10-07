/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges of a strikethrough (Strikethrough (extension)) whose opening and closing tildes may sit
/// on different lines. The range ends just past the closing tildes, on their own line.
@Suite("Multi-line strikethrough source ranges")
struct MultiLineStrikethroughEndTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The source range of the first `.strikethrough` node (DFS order) when `src` is parsed with
    /// `options`, or `nil` if no strikethrough forms.
    private func strikethroughRange(in src: String, options: MarkdownDocument.ParseOptions) -> Range<Pos>? {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> Range<Pos>? in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            for entry in ranges where entry.kind == .strikethrough {
                return entry.range
            }
            return nil
        }
    }

    /// Every node kind in DFS order.
    private func kinds(in src: String, options: MarkdownDocument.ParseOptions) -> [MarkdownNode.Kind] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [MarkdownNode.Kind] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges.map(\.kind)
        }
    }

    @Test("a two-line strikethrough ends on the closer's line")
    func twoLine() throws {
        let range = try #require(strikethroughRange(in: "~~a\nb~~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 4))
    }

    @Test("a three-line strikethrough ends on the closer's line")
    func threeLine() throws {
        let range = try #require(strikethroughRange(in: "~~a\nbb\ncc~~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 3, column: 5))
    }

    @Test("a two-line single-tilde strikethrough ends on the closer's line")
    func singleTilde() throws {
        let range = try #require(strikethroughRange(in: "~a\nb~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 3))
    }

    @Test("a single-line strikethrough spans opener through closer")
    func singleLine() throws {
        let range = try #require(strikethroughRange(in: "~~a~~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 1, column: 6))
    }

    @Test("a strikethrough closing before a soft line break stays on its line")
    func closesBeforeSoftBreak() throws {
        let range = try #require(strikethroughRange(in: "~~ab~~\ncd", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 1, column: 7))
    }

    @Test("a two-line strikethrough nested in emphasis ends on the closer's line")
    func nestedInEmphasis() throws {
        let src = "*~~a\nb~~*"
        let allKinds = kinds(in: src, options: Self.specOptions)
        #expect(allKinds.contains(.emphasis), "fixture must form an emphasis wrapper")
        let range = try #require(strikethroughRange(in: src, options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 2))
        #expect(range.upperBound == Pos(line: 2, column: 4))
    }

    @Test("a strikethrough crossing a backslash hard line break ends on the closer's line")
    func backslashHardBreak() throws {
        let range = try #require(strikethroughRange(in: "~~a\\\nb~~", options: Self.specOptions))
        #expect(range.lowerBound == Pos(line: 1, column: 1))
        #expect(range.upperBound == Pos(line: 2, column: 4))
    }
}
