/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind, text literal, and (for `^[…]`) attribute string. File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// AutolinkEmailPrecedingCharTests.dfsAutolinkNodes).
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

    /// The shipped parser's configuration.
    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .attributes]

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

    @Test("flag OFF: `^[](` newline `)` forms one attribute whose text is the newline")
    func attributeTextSpansSoftBreakWithoutCompatibility() {
        let ns = nodes(in: " ^[](\n)", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["\n"])
        #expect(ns.compactMap(\.text) == [])
    }

    @Test("flag OFF: `^[](x)` forms an attribute")
    func inlineAttributeSingleLineWithoutCompatibility() {
        let ns = nodes(in: "^[](x)", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["x"])
        #expect(ns.compactMap(\.text) == [])
    }

    @Test("flag OFF: ` ^[](x)` (leading space, no newline) forms an attribute")
    func inlineAttributeLeadingSpaceWithoutCompatibility() {
        let ns = nodes(in: " ^[](x)", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["x"])
        #expect(ns.compactMap(\.text) == [])
    }

    @Test("flag OFF: `^[x](/u)` keeps its inner text child and attribute string")
    func inlineAttributeWithInnerTextWithoutCompatibility() {
        let ns = nodes(in: "^[x](/u)", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute, .text])
        #expect(ns.compactMap(\.attrs) == ["/u"])
        #expect(ns.compactMap(\.text) == ["x"])
    }

    @Test("flag OFF: `[][]` (no caret) stays literal `[][]`")
    func plainEmptyBracketsWithoutCompatibility() {
        let ns = nodes(in: "[][]", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.attrs) == [])
        #expect(ns.compactMap(\.text) == ["[][]"])
    }

    @Test("flag OFF: `^[]` alone stays literal `^[]`")
    func emptyAttributeAloneWithoutCompatibility() {
        let ns = nodes(in: "^[]", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.attrs) == [])
        #expect(ns.compactMap(\.text) == ["^[]"])
    }

    @Test("flag OFF: `^[]x` keeps the trailing text")
    func emptyAttributeFollowedByTextWithoutCompatibility() {
        let ns = nodes(in: "^[]x", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.attrs) == [])
        #expect(ns.compactMap(\.text) == ["^[]x"])
    }

    /// The inline form completes the attribute, so a following label naming an attribute definition is text.
    @Test("flag OFF: a label following an inline form is text")
    func inlineAttributeThenResolvedReferenceWithoutCompatibility() {
        let ns = nodes(in: "^[lbl]: color: blue\n\n^[](x)[lbl]", options: Self.specOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute, .text])
        #expect(ns.compactMap(\.attrs) == ["x"])
        #expect(ns.compactMap(\.text) == ["[lbl]"])
    }
}
