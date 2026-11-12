/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A footnote-shaped bracket whose caret is backslash-escaped, `[\^…]`, is not a footnote reference; it is
/// literal text with the backslash removed (Backslash escapes).
@Suite("Backslash-escaped footnote caret `[\\^…]`")
struct FootnoteEscapedCaretLiteralTests {

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, literal: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc in
            dfs(doc)
        }
    }

    @Test("`[\\^x]` is text `[^x]`")
    func escapedCaretIsText() {
        let ns = nodes(in: "[\\^x]\n\n[^x]: n", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.literal) == ["[^x]"])
    }

    @Test("`![\\^x]` is text `![^x]`")
    func escapedCaretImageIsText() {
        let ns = nodes(in: "![\\^x]\n\n[^x]: n", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.literal) == ["![^x]"])
    }

    @Test("`[\\^\\nx]` is text `[^`, a soft line break, then text `x]`")
    func escapedCaretCrossLineKeepsSoftBreak() {
        let ns = nodes(in: "[\\^\nx]\n\n[^x]: n", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        #expect(ns.compactMap(\.literal) == ["[^", "x]"])
    }
}
