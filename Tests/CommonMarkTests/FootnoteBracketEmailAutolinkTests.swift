/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Appends every node's kind, literal text and link destination to `out`, in depth-first order.
private func dfsKindsTextAndURL(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsKindsTextAndURL(child, into: &out)
    }
}

@Suite("`[^[` footnote-shaped bracket next to an email autolink")
struct FootnoteBracketEmailAutolinkTests {

    private static let options: MarkdownDocument.ParseOptions = [.footnotes, .gfmAutolink, .attributes]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsKindsTextAndURL(doc.root, into: &out)
            return out
        }
    }

    @Test("`[^[]]f@f.f` is literal text: an extended autolink may not follow `]`")
    func bracketThenEmail() {
        let ns = nodes(in: "[^[]]f@f.f", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "[^[]]f@f.f"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`[^[]]*f@f.f` keeps the bracket literal and autolinks the email")
    func bracketThenDelimiterThenEmail() {
        let ns = nodes(in: "[^[]]*f@f.f", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "[^[]]*", nil, "f@f.f"])
        #expect(ns.compactMap(\.url) == ["mailto:f@f.f"])
    }

    @Test("`x[^[]]y` is literal text")
    func plainTrailingTextKept() {
        let ns = nodes(in: "x[^[]]y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "x[^[]]y"])
        #expect(ns.compactMap(\.url).isEmpty)
    }

    @Test("`f@f.f[^[]]y` autolinks the leading email and keeps the rest literal")
    func emailBeforeBracketKeepsTrailingText() {
        let ns = nodes(in: "f@f.f[^[]]y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "f@f.f", "[^[]]y"])
        #expect(ns.compactMap(\.url) == ["mailto:f@f.f"])
    }
}
