/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Spaces at the end of a line before a soft line break are removed (Soft line breaks), so a trailing
/// space after a link, emphasis or a code span produces no text node.
@Suite("Trailing space before a soft line break")
struct EmptyTextBeforeSoftBreakTests {

    private static let options: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The `(kind, literal)` of every node, in depth-first order.
    private func nodes(in src: String) -> [(kind: MarkdownNode.Kind, literal: String?)] {
        MarkdownDocument.withParsedDocument(src, options: Self.options) { dfs($0) }
    }

    @Test("emphasis + trailing space + soft line break: no empty text node")
    func emphasis() {
        let ns = nodes(in: "*x* \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .softBreak, .text])
        #expect(ns.compactMap(\.literal) == ["x", "y"])
    }

    @Test("code span + trailing space + soft line break: no empty text node")
    func codeSpan() {
        let ns = nodes(in: "`c` \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1), .softBreak, .text])
        // `literal()` also returns a code span's content.
        #expect(ns.compactMap(\.literal) == ["c", "y"])
    }

    @Test("link + trailing space + soft line break: no empty text node")
    func link() {
        let ns = nodes(in: "[foo] \n[]\n\n[foo]: /url \"title\"")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .softBreak, .text])
        #expect(ns.compactMap(\.literal) == ["foo", "[]"])
    }
}
