/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Appends each node's kind, literal and attribute string to `out` in document order.
private func dfsAttributeNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, attrs: String?)]
) {
    out.append((node.kind, node.literal(), node.attributes()))
    node.children.forEach { child in
        dfsAttributeNodes(child, into: &out)
    }
}

@Suite("Inline-attribute `^[` close-bracket handling")
struct InlineAttributesBracketTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .attributes]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, attrs: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, attrs: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, attrs: String?)] = []
            dfsAttributeNodes(doc.root, into: &out)
            return out
        }
    }

    @Test("`^[](` line ending `)` forms one attribute whose text is the line ending")
    func attributeTextSpansSoftBreak() {
        let ns = nodes(in: " ^[](\n)", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["\n"])
        #expect(ns.compactMap(\.text) == [])
    }

    @Test("`^[](x)` forms an attribute")
    func inlineAttributeSingleLine() {
        let ns = nodes(in: "^[](x)", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["x"])
        #expect(ns.compactMap(\.text) == [])
    }

    @Test("` ^[](x)` (leading space, no line ending) forms an attribute")
    func inlineAttributeLeadingSpace() {
        let ns = nodes(in: " ^[](x)", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["x"])
        #expect(ns.compactMap(\.text) == [])
    }

    @Test("`^[x](/u)` keeps its inner text child and attribute string")
    func inlineAttributeWithInnerText() {
        let ns = nodes(in: "^[x](/u)", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute, .text])
        #expect(ns.compactMap(\.attrs) == ["/u"])
        #expect(ns.compactMap(\.text) == ["x"])
    }

    @Test("`[][]` (no caret) stays literal `[][]`")
    func plainEmptyBrackets() {
        let ns = nodes(in: "[][]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.attrs) == [])
        #expect(ns.compactMap(\.text) == ["[][]"])
    }

    @Test("`^[]` alone stays literal `^[]`")
    func emptyAttributeAlone() {
        let ns = nodes(in: "^[]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.attrs) == [])
        #expect(ns.compactMap(\.text) == ["^[]"])
    }

    @Test("`^[]x` keeps the trailing text")
    func emptyAttributeFollowedByText() {
        let ns = nodes(in: "^[]x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.attrs) == [])
        #expect(ns.compactMap(\.text) == ["^[]x"])
    }

    /// The inline form completes the attribute, so a following label naming an attribute definition is text.
    @Test("a label following an inline form is text")
    func labelAfterInlineAttributeIsText() {
        let ns = nodes(in: "^[lbl]: color: blue\n\n^[](x)[lbl]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute, .text])
        #expect(ns.compactMap(\.attrs) == ["x"])
        #expect(ns.compactMap(\.text) == ["[lbl]"])
    }
}
