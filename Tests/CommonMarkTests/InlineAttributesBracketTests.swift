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

/// Two `^[…]` inline-attribute divergences the differential fuzzer found against cmark-gfm (via
/// swift-markdown@main), both in the `^[` attribute close-bracket handling.
///
/// **Finding 1 — `(…)` attribute text crossing a soft break.** A `^[](…)` whose attribute content
/// spans a paragraph line join (` ^[](\n)`) forms an attribute whose text is the newline. cmark's
/// `manual_scan_attribute_attributes` reads the flattened paragraph buffer, so the interior `\n` is
/// ordinary attribute content. The rewrite parses that paragraph as multi-segment content (the
/// leading space fixes a positive content indent, which under `.cmarkBugCompatibility` suppresses the
/// source-contiguity collapse), and its attribute scanner used to bail whenever the interior straddled
/// the interned-newline segment — leaving `^[](` + soft break + `)` as literal text. It now materializes
/// the interior into the arena (the tab-expansion pattern), matching the reference.
///
/// **Finding 2 — `^[]` followed by `[]`.** `^[][]` drops the trailing `[]`, leaving literal `^[]`.
/// cmark's `handle_close_bracket_attribute` calls `link_label`, which advances past the following
/// `[…]` even when the label is empty / resolves to no reference; the failure branch then emits a
/// single `]` at that ADVANCED position without rewinding (unlike the link path, which resets
/// `subj->pos = initial_pos`). So the `][` between the two brackets is consumed and never emitted.
@Suite("Inline-attribute `^[` close-bracket handling")
struct InlineAttributesBracketTests {

    /// The differential fuzzer's configuration: cmark bug-compatibility on, source positions on (the
    /// Markdown layer always tracks them). Finding 1 only reproduces here — the multi-segment paragraph
    /// path is gated on both.
    private static let fuzzOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, text: String?, attrs: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, attrs: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, attrs: String?)] = []
            dfsAttributeNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Finding 1: `(…)` attribute text crossing a soft break

    @Test("`^[](` newline `)` forms one attribute whose text is the newline")
    func attributeTextSpansSoftBreak() throws {
        let ns = try nodes(in: " ^[](\n)", options: Self.fuzzOptions)
        // Fixture sanity: a degenerate/empty tree must not pass vacuously.
        #expect(ns.count == 3)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        // No leftover text/soft-break siblings from a failed scan.
        #expect(!ns.map(\.kind).contains(.softBreak))
        let attr = try #require(ns.first { $0.kind == .attribute })
        #expect(attr.attrs == "\n")
    }

    @Test("control: `^[](x)` still forms an attribute (single line, unchanged)")
    func inlineAttributeSingleLine() throws {
        let ns = try nodes(in: "^[](x)", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["x"])
    }

    @Test("control: ` ^[](x)` (leading space, no newline) still forms an attribute")
    func inlineAttributeLeadingSpace() throws {
        let ns = try nodes(in: " ^[](x)", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["x"])
    }

    @Test("control: `^[x](/u)` keeps its inner text child and attribute string")
    func inlineAttributeWithInnerText() throws {
        let ns = try nodes(in: "^[x](/u)", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute, .text])
        #expect(ns.compactMap(\.attrs) == ["/u"])
        #expect(ns.compactMap(\.text) == ["x"])
    }

    // MARK: - Finding 2: `^[]` followed by `[]`

    @Test("`^[][]` drops the trailing `[]`, leaving literal `^[]`")
    func emptyAttributeFollowedByEmptyBrackets() throws {
        let ns = try nodes(in: "^[][]", options: Self.fuzzOptions)
        #expect(ns.count == 3)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["^[]"])
    }

    @Test("control: `[][]` (no caret) stays literal `[][]`")
    func plainEmptyBracketsUnchanged() throws {
        let ns = try nodes(in: "[][]", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[][]"])
    }

    @Test("control: `^[]` alone stays literal `^[]`")
    func emptyAttributeAloneUnchanged() throws {
        let ns = try nodes(in: "^[]", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["^[]"])
    }

    @Test("control: `^[]x` keeps the trailing text")
    func emptyAttributeFollowedByTextUnchanged() throws {
        let ns = try nodes(in: "^[]x", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["^[]x"])
    }

    // MARK: - Finding 2 corollary: a `[label]` following a matched inline `(attrs)` form

    // cmark calls `link_label` unconditionally, so a `[…]` after a matched `(attrs)` form is consumed
    // too. An unresolved label leaves the inline attributes intact but is still dropped from the tree;
    // a resolved attribute reference overwrites the inline attributes (`ref->is_attributes_reference`).

    @Test("`^[](x)[undef]` consumes the unresolved label, keeping the inline attributes")
    func inlineAttributeThenUnresolvedLabel() throws {
        let ns = try nodes(in: "^[](x)[undef]", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["x"])
    }

    @Test("`^[](x)[undef]y` consumes the label but keeps text after it")
    func inlineAttributeThenUnresolvedLabelThenText() throws {
        let ns = try nodes(in: "^[](x)[undef]y", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute, .text])
        #expect(ns.compactMap(\.attrs) == ["x"])
        #expect(ns.compactMap(\.text) == ["y"])
    }

    @Test("a resolved attribute reference following an inline form overwrites its attributes")
    func inlineAttributeThenResolvedReference() throws {
        let ns = try nodes(in: "^[lbl]: color: blue\n\n^[](x)[lbl]", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .attribute])
        #expect(ns.compactMap(\.attrs) == ["color: blue"])
    }
}
