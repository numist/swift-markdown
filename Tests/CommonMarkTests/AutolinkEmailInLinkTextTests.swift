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
// AutolinkEmptySiblingTests.dfsAutolinkNodes).
private func dfsInLinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsInLinkNodes(child, into: &out)
    }
}

/// A bare GFM email inside an existing link's text.
///
/// cmark's autolink `postprocess` (`extensions/autolink.c`) tracks link context with a single `in_link`
/// BOOLEAN, not a nesting depth: entering a link arms it and exiting ANY link clears it. So when a link
/// is nested inside another link's text - e.g. the angle autolink `<M@C>` in `[<M@C>B@.B]()` - exiting
/// the inner autolink clears `in_link`, and the OUTER link's remaining text (`B@.B`) is autolinked into a
/// nested email link with the empty `before`/`after` Text siblings the extension always emits.
///
/// A link nested in a link is invalid HTML/CommonMark, so the shipped (spec-correct) parser leaves the
/// bare email as text. A bare email in plain paragraph text (not inside any link) autolinks
/// identically in both modes - the control that the traversal change does not perturb normal autolinking.
@Suite("GFM bare email inside link text (cmark bug-for-bug)")
struct AutolinkEmailInLinkTextTests {

    /// The shipped configuration: GFM autolink on.
    private static let flagOff: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsInLinkNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Flag OFF: spec-correct, the bare email stays text

    @Test("flag-OFF: bare email inside link text is NOT autolinked")
    func bareEmailInLinkTextFlagOff() {
        // A link inside a link is invalid (spec "Links"), so `B@b.c` stays text in the link's text.
        let ns = nodes(in: "[x B@b.c]()", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "x B@b.c"])
        #expect(ns.compactMap(\.url) == [""])
    }

    // MARK: - Both modes: a bare email in plain text (no enclosing link) is unchanged

    @Test("bare email in plain paragraph text autolinks identically in BOTH modes")
    func bareEmailInPlainTextBothModes() {
        // `x B@b.B y` - the email is NOT inside a link; genuine text on both sides means no empty siblings.
        // This is the control: the in-link traversal change
        // must not perturb ordinary email autolinking.
        let ns = nodes(in: "x B@b.B y", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "B@b.B", " y"])
        #expect(ns.compactMap(\.url) == ["mailto:B@b.B"])
    }
}
