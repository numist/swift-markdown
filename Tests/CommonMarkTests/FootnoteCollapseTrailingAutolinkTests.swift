/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind, text literal, and (for links) destination URL. File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// AutolinkEmailPrecedingCharTests.dfsAutolinkNodes).
private func dfsCollapseNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsCollapseNodes(child, into: &out)
    }
}

@Suite("`[^[` footnote-collapse followed by an email autolink")
struct FootnoteCollapseTrailingAutolinkTests {

    /// The shipped configuration: footnotes, GFM autolink, and inline attributes on.
    private static let flagOff: MarkdownDocument.ParseOptions = [.footnotes, .gfmAutolink, .attributes]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsCollapseNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Control: the shipped deliverable stays spec-correct

    @Test("flag-OFF: `[^[]]f@f.f` keeps the bracket literal and still autolinks the email")
    func collapseThenEmailFlagOff() {
        // The bracket is literal `[^[]]` and the email autolinks with no
        // trailing empty sibling (spec-correct clean tree).
        let ns = nodes(in: "[^[]]f@f.f", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "[^[]]", nil, "f@f.f"])
        #expect(ns.compactMap(\.url) == ["mailto:f@f.f"])
    }

    /// An undefined footnote reference is literal text and nothing in it is dropped, whereas cmark-gfm reconstructs the
    /// bracket to `[^[` followed by a NUL and so loses the text after it.
    @Test("flag-OFF: `x[^[]]y` keeps the bracket and the trailing text literal")
    func plainTrailingTextKeptFlagOff() {
        let ns = nodes(in: "x[^[]]y", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "x[^[]]y"])
        #expect(ns.compactMap(\.url).isEmpty)
    }

    /// The leading email autolinks and the undefined footnote reference after it stays literal text with nothing
    /// dropped, whereas cmark-gfm truncates the text after the address to `[^[` and adds an empty text node before
    /// the link.
    @Test("flag-OFF: `f@f.f[^[]]y` links the leading email and keeps the trailing text literal")
    func emailBeforeBracketKeepsTrailingTextFlagOff() {
        let ns = nodes(in: "f@f.f[^[]]y", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "f@f.f", "[^[]]y"])
        #expect(ns.compactMap(\.url) == ["mailto:f@f.f"])
    }
}
