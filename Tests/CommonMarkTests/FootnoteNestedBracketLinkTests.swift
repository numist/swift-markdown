/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind and text literal. File-scope + `borrowing MarkdownNode` to satisfy the
// noncopyable-borrow rules (see AutolinkEmailPrecedingCharTests.dfsAutolinkNodes).
private func dfsKindText(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsKindText(child, into: &out)
    }
}

// Depth-annotated variant: pins the parent/child nesting the flat `dfsKindText` can't distinguish
// (a node nested inside an attribute vs. a sibling of an empty attribute flatten to the same list).
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

@Suite("`[^[` footnote-collapse nested inside a link bracket")
struct FootnoteNestedBracketLinkTests {

    /// The shipped configuration.
    private static let shippedOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes, .attributes]

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

    // MARK: - Controls: the inner `]` is immediately followed by `()`, so no collapse

    @Test("control: `[^[]]()` forms a link whose text is `^[]` (no collapse)")
    func caretBracketImmediateParensFormsLink() {
        let shipped = nodes(in: "[^[]]()", options: Self.shippedOptions)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(shipped.compactMap(\.text) == ["^[]"])
    }

    @Test("control: `[[^[]]()` is literal `[` plus a link whose text is `^[]`")
    func caretBracketPrefixedLink() {
        let shipped = nodes(in: "[[^[]]()", options: Self.shippedOptions)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(shipped.compactMap(\.text) == ["[", "^[]"])
    }

    // MARK: - Controls: neighbouring shapes with no `()` and no full close

    @Test("control: `[^[]` stays literal `[^[]`")
    func caretBracketUnclosedStaysLiteral() {
        let shipped = nodes(in: "[^[]", options: Self.shippedOptions)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text])
        #expect(shipped.compactMap(\.text) == ["[^[]"])
    }

    @Test("control: `[^[]()` is literal `[` plus an empty inline attribute (attribute path, unaffected)")
    func caretBracketSingleCloseIsAttribute() {
        let shipped = nodes(in: "[^[]()", options: Self.shippedOptions)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text, .attribute])
        #expect(shipped.compactMap(\.text) == ["["])
    }

    // MARK: - The inner `^[…]()` / `^[…](…)` forms an attribute, so the collapse must NOT fire

    @Test("`[^[]()]`: the inner `^[]()` is an empty attribute, so `[` + attribute + `]` (no collapse)")
    func caretBracketAttributeInsideOuterBracket() {
        let shipped = nodes(in: "[^[]()]", options: Self.shippedOptions)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text, .attribute, .text])
        #expect(shipped.compactMap(\.text) == ["[", "]"])
    }

    @Test("`[^[x](y)]`: the inner `^[x](y)` is a non-empty attribute wrapping `x`, so `[` + attribute[`x`] + `]`")
    func caretBracketNonEmptyAttributeInsideOuterBracket() {
        let shipped = depthNodes(in: "[^[x](y)]", options: Self.shippedOptions)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text, .attribute, .text, .text])
        // Depths pin the nesting: `x` (depth 3) is the attribute's child, while `[` and `]` (depth 2)
        // are its siblings — a flat kind list alone can't distinguish this from an empty attribute.
        #expect(shipped.map(\.depth) == [0, 1, 2, 2, 3, 2])
        #expect(shipped.compactMap(\.text) == ["[", "x", "]"])
    }

    // MARK: - Shipped configuration: an undefined footnote reference is literal text

    /// An undefined footnote reference is literal text, so the outer `[…]()` is a link whose text is the whole
    /// `[^[]]`, whereas cmark-gfm truncates the reference to `[^[`.
    @Test("shipped: `[[^[]]]()` is a link whose text is `[^[]]`")
    func nestedCaretBracketFormsLinkShipped() {
        let ns = nodes(in: "[[^[]]]()", options: Self.shippedOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.text) == ["[^[]]"])
    }

    /// An undefined footnote reference is literal text, whereas cmark-gfm truncates it to `[^[`.
    @Test("shipped: `[^[]]` stays literal `[^[]]`")
    func caretBracketTopLevelShipped() {
        let ns = nodes(in: "[^[]]", options: Self.shippedOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^[]]"])
    }

    /// An undefined footnote reference is literal text and the text after it is kept, whereas cmark-gfm truncates
    /// the run to `x[^[`.
    @Test("shipped: `x[^[]]y` stays literal `x[^[]]y`")
    func caretBracketKeepsTrailingTextShipped() {
        let ns = nodes(in: "x[^[]]y", options: Self.shippedOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["x[^[]]y"])
    }

    /// Brackets with no link destination around an undefined footnote reference are literal text, whereas cmark-gfm
    /// truncates the run to `[[^[`.
    @Test("shipped: `[[^[]]]` stays literal `[[^[]]]`")
    func nestedCaretBracketWithoutParensShipped() {
        let ns = nodes(in: "[[^[]]]", options: Self.shippedOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[[^[]]]"])
    }

    /// An undefined footnote reference is literal text, whereas cmark-gfm truncates it to `[^[`.
    @Test("shipped: `[^[]y]` stays literal `[^[]y]`")
    func caretBracketNonAttributeInsideOuterBracketShipped() {
        let ns = nodes(in: "[^[]y]", options: Self.shippedOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^[]y]"])
    }
}
