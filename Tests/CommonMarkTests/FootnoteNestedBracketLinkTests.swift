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

/// A footnotes bug-compatibility divergence the differential fuzzer found against cmark-gfm (via
/// swift-markdown@main): `[[^[]]]()` must form a `Link` whose text is `[^[`, not stay literal `[[^[`.
///
/// The `[^[` footnote-collapse (FINDINGS #146) reproduces cmark's inline footnote branch on a
/// footnote-shaped bracket whose caret is immediately followed by another `[`. cmark captures that
/// bracket's label from the static `"^["` string, over-reading past the inner `[` into the string's
/// NUL terminator; the unresolved reference reconstructs to `[^[` followed by a NUL, and reading the
/// consolidated run as a C-string truncates there. cmark **continues** parsing after this, so an
/// enclosing bracket can still close: in `[[^[]]]()` the inner `[^[` collapses to the text `[^[`, then
/// the outer `[…]()` forms a link around it. The rewrite previously consumed the rest of the line at
/// the collapse, which dropped the outer `]()` and left literal `[[^[`; it now emits `[^[`, marks that
/// text node run-truncating (so `consolidateTextNodes` drops the text it swallows), and keeps parsing.
///
/// The collapse fires only when the inner `[^[`'s `]` is *not* immediately followed by link syntax; the
/// controls below (`[^[]]()`, `[[^[]]()`) close the inner bracket straight into `()` and so form a link
/// with text `^[]` via the ordinary inline-link path, never reaching the collapse.
@Suite("`[^[` footnote-collapse nested inside a link bracket")
struct FootnoteNestedBracketLinkTests {

    /// The differential fuzzer's configuration for this class: footnotes on, cmark bug-compatibility on,
    /// source positions on (the Markdown layer always tracks them). The collapse is gated on both
    /// footnotes and `.cmarkBugCompatibility`.
    private static let fuzzOptions: MarkdownDocument.ParseOptions =
        [.sourcePosition, .cmarkBugCompatibility, .footnotes]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, text: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?)] = []
            dfsKindText(doc.root, into: &out)
            return out
        }
    }

    // MARK: - The finding

    @Test("`[[^[]]]()`: the inner `[^[` collapses to link text and the outer `[…]()` forms the link")
    func nestedCaretBracketFormsLink() throws {
        let ns = try nodes(in: "[[^[]]]()", options: Self.fuzzOptions)
        // Fixture sanity: a degenerate/empty tree must not pass vacuously.
        #expect(ns.count == 4)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.text) == ["[^["])
    }

    // MARK: - Controls: the collapse fires with no enclosing link that forms

    @Test("control: `[^[]]` (no enclosing bracket) collapses to literal `[^[`")
    func caretBracketTopLevelCollapse() throws {
        let ns = try nodes(in: "[^[]]", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^["])
    }

    @Test("control: `x[^[]]y` collapses to `x[^[`, dropping the swallowed trailing text")
    func caretBracketCollapseDropsTrailingText() throws {
        let ns = try nodes(in: "x[^[]]y", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["x[^["])
    }

    @Test("control: `[[^[]]]` (no `()`) stays literal `[[^[`")
    func nestedCaretBracketWithoutParens() throws {
        let ns = try nodes(in: "[[^[]]]", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[[^["])
    }

    // MARK: - Controls: the inner `]` is immediately followed by `()`, so no collapse

    @Test("control: `[^[]]()` forms a link whose text is `^[]` (no collapse)")
    func caretBracketImmediateParensFormsLink() throws {
        let ns = try nodes(in: "[^[]]()", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.text) == ["^[]"])
    }

    @Test("control: `[[^[]]()` is literal `[` plus a link whose text is `^[]`")
    func caretBracketPrefixedLink() throws {
        let ns = try nodes(in: "[[^[]]()", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.compactMap(\.text) == ["[", "^[]"])
    }

    // MARK: - Controls: neighbouring shapes with no `()` and no full close

    @Test("control: `[^[]` stays literal `[^[]`")
    func caretBracketUnclosedStaysLiteral() throws {
        let ns = try nodes(in: "[^[]", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^[]"])
    }

    @Test("control: `[^[]()` is literal `[` plus an empty inline attribute (attribute path, unaffected)")
    func caretBracketSingleCloseIsAttribute() throws {
        let ns = try nodes(in: "[^[]()", options: Self.fuzzOptions)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .attribute])
        #expect(ns.compactMap(\.text) == ["["])
    }
}
