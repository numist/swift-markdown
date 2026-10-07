/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// The two or more spaces before a hard line break belong to the break (Hard line breaks), so they
/// produce no text node and are not part of a preceding text node's source range.
@Suite("Trailing spaces before a hard line break")
struct EmptyTextBeforeHardBreakTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The `(kind, text)` of every node, in depth-first order.
    private func nodes(in src: String) -> [(kind: MarkdownNode.Kind, text: String?)] {
        MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, text: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?)] = []
            dfsKindsAndText(doc.root, into: &out)
            return out
        }
    }

    /// The source range of every text node, in depth-first order.
    private func textRanges(in src: String) -> [Range<Pos>?] {
        let ranges = MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.filter { $0.kind == .text }.map { $0.range }
    }

    @Test("literal ] before a hard line break keeps its 1-character range")
    func bracketLiteral() throws {
        let ns = nodes(in: "]  \n]")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        #expect(ns.compactMap(\.text) == ["]", "]"])
        let texts = textRanges(in: "]  \n]")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // first "]"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 2))
    }

    @Test("emphasis + trailing spaces + hard line break: no empty text node")
    func emphasis() {
        let ns = nodes(in: "*x*  \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .lineBreak, .text])
        #expect(ns.compactMap(\.text) == ["x", "y"])
    }

    @Test("inline code + trailing spaces + hard line break: no empty text node")
    func inlineCode() {
        let ns = nodes(in: "`c`  \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1), .lineBreak, .text])
        // `literal()` also returns inline code content.
        #expect(ns.compactMap(\.text) == ["c", "y"])
    }

    @Test("link + trailing spaces + hard line break: no empty text node")
    func link() {
        let ns = nodes(in: "[foo]  \n[]\n\n[foo]: /url \"title\"")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .lineBreak, .text])
        #expect(ns.compactMap(\.text) == ["foo", "[]"])
    }
}
