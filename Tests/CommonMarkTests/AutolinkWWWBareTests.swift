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

/// An extended www autolink's domain holds a period among the characters the domain scan examines, which stops
/// short of the final character of the inline content; the trailing punctuation trim may then cut the link back
/// to `www`.
@Suite("Extended www autolink without a domain")
struct AutolinkWWWBareTests {

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

    @Test("`www.` followed by a space links `www`")
    func domainlessWWWLinksWWW() {
        let ns = nodes(in: "www. x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www", ". x"])
        #expect(ns.compactMap(\.url) == ["http://www"])
    }

    @Test("`www.` at the end of the input is text")
    func wwwAtEndOfInputNotLinked() {
        let ns = nodes(in: "www.", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "www."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`www.a.b` autolinks")
    func validDomainAutolinks() {
        let ns = nodes(in: "www.a.b x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b", " x"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b"])
    }

    @Test("`www._` is text")
    func domainlessWWWUnderscoreNotLinked() {
        let ns = nodes(in: "www._ x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "www._ x"])
        #expect(ns.compactMap(\.url) == [])
    }
}
