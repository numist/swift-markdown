/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

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

/// An extended url or www autolink (Autolinks (extension)) is recognized only at the start of a line, after
/// whitespace, or after `*`, `_`, `~` or `(`.
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

    /// Assert that `src` parses to a single `.text` node with literal `literal` and no link.
    private func expectText(_ src: String, literal: String) {
        let ns = nodes(in: src, options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, literal])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("scheme is text after `!`")
    func afterBang() {
        expectText("!http://e.e", literal: "!http://e.e")
    }

    @Test("scheme is text after `.`")
    func afterDot() {
        expectText(".http://e.e", literal: ".http://e.e")
    }

    @Test("scheme is text after a digit")
    func afterDigit() {
        expectText("9http://e.e", literal: "9http://e.e")
    }

    @Test("scheme is text after `-`")
    func afterHyphen() {
        expectText("-http://e.e", literal: "-http://e.e")
    }

    @Test("scheme is text after `/`")
    func afterSlash() {
        expectText("/http://e.e", literal: "/http://e.e")
    }

    @Test("scheme is text after a non-ASCII letter")
    func afterNonASCIILetter() {
        expectText("éhttp://e.e", literal: "éhttp://e.e")
    }

    @Test("scheme is text after a NUL (replaced with U+FFFD)")
    func afterNUL() {
        // A NUL is replaced with U+FFFD (Insecure characters).
        expectText("\u{0}http://e.e", literal: "\u{FFFD}http://e.e")
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
