/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

// Depth-first: each node's kind, text literal, and (for links) destination URL.
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// An extended url autolink's scheme is the whole run of ASCII letters before `://`, so the autolink may follow any
/// character but a letter. An extended www autolink comes only at the start of a line, after whitespace, or after
/// `*`, `_`, `~` or `(`.
@Suite("Extended autolink preceding character")
struct AutolinkSchemePrecedingCharTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    /// Assert that `src` parses to a leading `.text` node with literal `prefix` followed by a
    /// `Link(http://e.e)` whose visible text is `http://e.e`.
    private func expectPrefixThenLink(_ src: String, prefix: String) {
        let ns = nodes(in: src, options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, prefix, nil, "http://e.e"])
        #expect(ns.compactMap(\.url) == ["http://e.e"])
    }

    @Test("scheme autolinks after `!`")
    func afterBang() {
        expectPrefixThenLink("!http://e.e", prefix: "!")
    }

    @Test("scheme autolinks after `.`")
    func afterDot() {
        expectPrefixThenLink(".http://e.e", prefix: ".")
    }

    @Test("scheme autolinks after a digit")
    func afterDigit() {
        expectPrefixThenLink("9http://e.e", prefix: "9")
    }

    @Test("scheme autolinks after `-`")
    func afterHyphen() {
        expectPrefixThenLink("-http://e.e", prefix: "-")
    }

    @Test("scheme autolinks after `/`")
    func afterSlash() {
        expectPrefixThenLink("/http://e.e", prefix: "/")
    }

    @Test("scheme autolinks after a non-ASCII letter")
    func afterNonASCIILetter() {
        expectPrefixThenLink("éhttp://e.e", prefix: "é")
    }

    @Test("scheme autolinks after a NUL (replaced with U+FFFD)")
    func afterNUL() {
        // A NUL is replaced with U+FFFD (Insecure characters).
        expectPrefixThenLink("\u{0}http://e.e", prefix: "\u{FFFD}")
    }

    @Test("scheme autolinks after `*`, `_` or `~`", arguments: ["*", "_", "~"])
    func afterDelimiter(_ delimiter: String) {
        expectPrefixThenLink(delimiter + "http://e.e", prefix: delimiter)
    }

    @Test("an ASCII letter before the scheme is text")
    func alphaBeforeSchemeNoLink() {
        // The `x` is part of the scheme `xhttp`.
        let ns = nodes(in: "xhttp://e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "xhttp://e.e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("scheme autolinks after `(`")
    func afterParen() {
        expectPrefixThenLink("(http://e.e", prefix: "(")
    }

    @Test("scheme autolinks after a leading space")
    func afterLeadingSpace() {
        // A paragraph's initial spaces are stripped (Paragraphs).
        let ns = nodes(in: " http://e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://e.e"])
        #expect(ns.compactMap(\.url) == ["http://e.e"])
    }

    // MARK: - Extended www autolinks

    @Test("`www.` is text after `!`")
    func wwwAfterBangIsText() {
        let ns = nodes(in: "!www.e.f", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "!www.e.f"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`www.` autolinks after `(`")
    func wwwAfterParenAutolinks() {
        let ns = nodes(in: "(www.e.f", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "(", nil, "www.e.f"])
        #expect(ns.compactMap(\.url) == ["http://www.e.f"])
    }
}
