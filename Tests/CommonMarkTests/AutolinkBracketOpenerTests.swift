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

/// An extended url or www autolink (Autolinks (extension)) doesn't form while an unclosed `[` or `![` opener
/// precedes it in the same inline content.
@Suite("Extended autolinks after an unclosed bracket")
struct AutolinkBracketOpenerTests {

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

    @Test("unclosed `[` before a scheme URL leaves it as text")
    func openBracketSuppressesSchemeAutolink() {
        let ns = nodes(in: "[http://t.t", options: Self.options)
        #expect(ns.count == 3)
        #expect(!ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "[http://t.t"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("unclosed `![` before a scheme URL leaves it as text")
    func openImageBracketSuppressesSchemeAutolink() {
        let ns = nodes(in: "![http://t.t", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "![http://t.t"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("a scheme URL with no leading `[` autolinks")
    func bareSchemeAutolinks() {
        let ns = nodes(in: "http://t.t", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://t.t"])
        #expect(ns.compactMap(\.url) == ["http://t.t"])
    }

    @Test("`[x](http://t.t)` is an inline link")
    func closedLinkParses() {
        let ns = nodes(in: "[x](http://t.t)", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "x"])
        #expect(ns.compactMap(\.url) == ["http://t.t"])
    }

    @Test("a scheme URL after a closed `[…]` autolinks")
    func afterClosedBracketAutolinks() {
        let ns = nodes(in: "[a] http://t.t", options: Self.options)
        #expect(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://t.t"])
    }
}
