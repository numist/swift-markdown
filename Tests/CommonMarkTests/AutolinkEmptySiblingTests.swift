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

/// An extended autolink's sibling text nodes hold the text around it, with no empty text node where nothing
/// precedes or follows it.
@Suite("Text around extended autolinks")
struct AutolinkEmptySiblingTests {

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

    @Test("www autolink between text")
    func wwwMidText() {
        let ns = nodes(in: "x www.example.com y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "www.example.com", " y"])
        #expect(ns.compactMap(\.url) == ["http://www.example.com"])
    }

    @Test("scheme URL after text")
    func schemeURLAfterText() {
        let ns = nodes(in: "x https://y.io", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "https://y.io"])
        #expect(ns.compactMap(\.url) == ["https://y.io"])
    }

    @Test("www autolink alone")
    func wwwAtStart() {
        let ns = nodes(in: "www.example.com", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.example.com"])
        #expect(ns.compactMap(\.url) == ["http://www.example.com"])
    }

    @Test("email autolink alone")
    func emailAlone() {
        let ns = nodes(in: "o@x.x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@x.x"])
        #expect(ns.compactMap(\.url) == ["mailto:o@x.x"])
    }

    @Test("scheme URL alone")
    func schemeURLAlone() {
        let ns = nodes(in: "https://x.io", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "https://x.io"])
        #expect(ns.compactMap(\.url) == ["https://x.io"])
    }

    @Test("email autolink before text")
    func emailTrailingText() {
        let ns = nodes(in: "o@x.x y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@x.x", " y"])
        #expect(ns.compactMap(\.url) == ["mailto:o@x.x"])
    }

    @Test("email autolink before emphasis")
    func emailBeforeEmphasis() {
        let ns = nodes(in: "o@x.x*a*", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .emphasis, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@x.x", nil, "a"])
        #expect(ns.compactMap(\.url) == ["mailto:o@x.x"])
    }
}
