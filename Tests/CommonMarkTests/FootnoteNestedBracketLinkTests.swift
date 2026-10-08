/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Appends every node's kind and literal text to `out`, in depth-first order.
private func dfsKindText(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsKindText(child, into: &out)
    }
}

/// Like `dfsKindText`, with each node's depth, which tells a child of an inline attribute from its sibling.
private func dfsDepthKind(
    _ node: borrowing MarkdownNode,
    depth: Int,
    into out: inout [(depth: Int, kind: MarkdownNode.Kind, text: String?)]
) {
    out.append((depth, node.kind, node.literal()))
    node.children.forEach { child in
        dfsDepthKind(child, depth: depth + 1, into: &out)
    }
}

@Suite("`[^[` footnote-shaped bracket inside a link bracket")
struct FootnoteNestedBracketLinkTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes, .attributes]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?)] = []
            dfsKindText(doc.root, into: &out)
            return out
        }
    }

    private func depthNodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(depth: Int, kind: MarkdownNode.Kind, text: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(depth: Int, kind: MarkdownNode.Kind, text: String?)] in
            var out: [(depth: Int, kind: MarkdownNode.Kind, text: String?)] = []
            dfsDepthKind(doc.root, depth: 0, into: &out)
            return out
        }
    }

    // MARK: - `]()` closes a link

    @Test("`[^[]]()` forms a link whose text is `^[]`")
    func caretBracketImmediateParensFormsLink() {
        let ns = nodes(in: "[^[]]()", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.text) == ["^[]"])
    }

    @Test("`[[^[]]()` is literal `[` plus a link whose text is `^[]`")
    func caretBracketPrefixedLink() {
        let ns = nodes(in: "[[^[]]()", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.compactMap(\.text) == ["[", "^[]"])
    }

    // MARK: - Unclosed and single-close shapes

    @Test("`[^[]` stays literal `[^[]`")
    func caretBracketUnclosedStaysLiteral() {
        let ns = nodes(in: "[^[]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^[]"])
    }

    @Test("`[^[]()` is literal `[` plus an empty inline attribute")
    func caretBracketSingleCloseIsAttribute() {
        let ns = nodes(in: "[^[]()", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .attribute])
        #expect(ns.compactMap(\.text) == ["["])
    }

    // MARK: - An inner `^[…](…)` is an inline attribute

    @Test("`[^[]()]`: the inner `^[]()` is an empty attribute, so `[` + attribute + `]`")
    func caretBracketAttributeInsideOuterBracket() {
        let ns = nodes(in: "[^[]()]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .attribute, .text])
        #expect(ns.compactMap(\.text) == ["[", "]"])
    }

    @Test("`[^[x](y)]`: the inner `^[x](y)` is a non-empty attribute wrapping `x`, so `[` + attribute[`x`] + `]`")
    func caretBracketNonEmptyAttributeInsideOuterBracket() {
        let ns = depthNodes(in: "[^[x](y)]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .attribute, .text, .text])
        // Depths pin the nesting: `x` (depth 3) is the attribute's child, while `[` and `]` (depth 2)
        // are its siblings — a flat kind list alone can't distinguish this from an empty attribute.
        #expect(ns.map(\.depth) == [0, 1, 2, 2, 3, 2])
        #expect(ns.compactMap(\.text) == ["[", "x", "]"])
    }

    // MARK: - `[^[…]` is literal text

    // `[^[` opens no footnote reference, because a label may not contain an unescaped `[` (Links).

    @Test("`[[^[]]]()` is a link whose text is `[^[]]`")
    func nestedCaretBracketFormsLink() {
        let ns = nodes(in: "[[^[]]]()", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.text) == ["[^[]]"])
    }

    @Test("`[^[]]` stays literal `[^[]]`")
    func caretBracketTopLevelStaysLiteral() {
        let ns = nodes(in: "[^[]]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^[]]"])
    }

    @Test("`x[^[]]y` stays literal `x[^[]]y`")
    func caretBracketKeepsTrailingText() {
        let ns = nodes(in: "x[^[]]y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["x[^[]]y"])
    }

    @Test("`[[^[]]]` stays literal `[[^[]]]`")
    func nestedCaretBracketWithoutParens() {
        let ns = nodes(in: "[[^[]]]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[[^[]]]"])
    }

    @Test("`[^[]y]` stays literal `[^[]y]`")
    func caretBracketNonAttributeInsideOuterBracket() {
        let ns = nodes(in: "[^[]y]", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^[]y]"])
    }
}
