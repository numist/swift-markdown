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
private func dfsInLinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsInLinkNodes(child, into: &out)
    }
}

/// Links may not contain other links (Links), so an email address in link text is not an extended email
/// autolink.
@Suite("Extended email autolinks in link text")
struct AutolinkEmailInLinkTextTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsInLinkNodes(doc.root, into: &out)
            return out
        }
    }

    @Test("an email address inside link text is text")
    func bareEmailInLinkText() {
        let ns = nodes(in: "[x B@b.c]()", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "x B@b.c"])
        #expect(ns.compactMap(\.url) == [""])
    }

    @Test("an email address in paragraph text autolinks")
    func bareEmailInPlainText() {
        let ns = nodes(in: "x B@b.B y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "B@b.B", " y"])
        #expect(ns.compactMap(\.url) == ["mailto:B@b.B"])
    }
}
