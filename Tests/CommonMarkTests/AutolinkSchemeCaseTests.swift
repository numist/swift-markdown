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

/// The scheme of an extended url autolink (Autolinks (extension)) matches `http://`, `https://` or `ftp://` in any
/// case, and the destination and link text keep the source's case.
@Suite("Extended url autolink scheme case")
struct AutolinkSchemeCaseTests {

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

    /// Assert that `src` parses to a paragraph holding only a link to `link` whose text is `link`.
    private func expectWholeSourceLinks(_ src: String, link: String) {
        let ns = nodes(in: src, options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, link])
        #expect(ns.compactMap(\.url) == [link])
    }

    @Test("upper-case `HTTP://` links, preserving case")
    func upperHTTP() {
        expectWholeSourceLinks("HTTP://e.e", link: "HTTP://e.e")
    }

    @Test("title-case `Http://` links, preserving case")
    func titleHTTP() {
        expectWholeSourceLinks("Http://e.e", link: "Http://e.e")
    }

    @Test("mixed-case `hTTp://` links, preserving case")
    func mixedHTTP() {
        expectWholeSourceLinks("hTTp://e.e", link: "hTTp://e.e")
    }

    @Test("upper-case `HTTPS://` links, preserving case")
    func upperHTTPS() {
        expectWholeSourceLinks("HTTPS://x.io", link: "HTTPS://x.io")
    }

    @Test("upper-case `FTP://` links, preserving case")
    func upperFTP() {
        expectWholeSourceLinks("FTP://x.io", link: "FTP://x.io")
    }

    @Test("lower-case `http://` links")
    func lowerHTTP() {
        expectWholeSourceLinks("http://e.e", link: "http://e.e")
    }

    @Test("another scheme (`xttp://`) is text")
    func unrecognizedSchemeNoLink() {
        let ns = nodes(in: "xttp://e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "xttp://e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`WWW.` is not `www.`, so it is text")
    func wwwIsCaseSensitive() {
        let ns = nodes(in: "WWW.e.f", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "WWW.e.f"])
        #expect(ns.compactMap(\.url) == [])
    }
}
