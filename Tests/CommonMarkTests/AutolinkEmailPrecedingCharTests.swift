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

/// An extended email autolink (Autolinks (extension)) is recognized only at the start of a line, after whitespace,
/// or after `*`, `_`, `~` or `(`.
@Suite("Extended email autolink preceding character")
struct AutolinkEmailPrecedingCharTests {

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

    @Test("email is text after a leading `<`")
    func emailAfterAngle() {
        // Without a `>`, the `<` is literal text.
        let ns = nodes(in: "<o@e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "<o@e.e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("standalone email autolinks")
    func emailStandalone() {
        let ns = nodes(in: "o@e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    @Test("email after text and a space autolinks")
    func emailAfterTextSpace() {
        let ns = nodes(in: "x o@e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    @Test("email after `(` autolinks")
    func emailAfterParen() {
        let ns = nodes(in: "(o@e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "(", nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    // MARK: - Local-part characters

    // An extended email autolink's local part holds only alphanumerics, `.`, `-`, `_` and `+`, unlike the email
    // address of an email autolink (Autolinks), which admits characters such as `!`.

    @Test("`<a!@e.e` is text: `!` is not a local-part character")
    func bangBeforeAtNoLink() {
        let ns = nodes(in: "<a!@e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "<a!@e.e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`x!@e.e` at the start of a line is text")
    func bangLocalAtStartNoLink() {
        let ns = nodes(in: "x!@e.e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "x!@e.e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("an email autolink admits `!` in its local part")
    func angleEmailKeepsBroadLocalSet() {
        let ns = nodes(in: "<a!b@c.de>", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a!b@c.de"])
        #expect(ns.compactMap(\.url) == ["mailto:a!b@c.de"])
    }
}
