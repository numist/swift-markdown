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

/// A footnotes bug-compatibility divergence the differential fuzzer found against cmark-gfm (via
/// swift-markdown@main): after a `[^[` footnote collapse, a trailing email must still autolink.
///
/// The `[^[` footnote-collapse (FINDINGS #146, #168) reproduces cmark's inline footnote branch on a
/// footnote-shaped bracket whose caret is immediately followed by another `[`. cmark reads the label from
/// the static `"^["` string, over-reading past the inner `[` into the string's NUL terminator, so
/// `process_footnotes` reconstructs the reference to the bytes `[^[` + NUL + `]`. `cmark_consolidate_text_nodes`
/// then merges that node with the following text, and the autolink `postprocess` (which runs *after*
/// consolidation) splits any email out of the merged run into a `Link`. Only at render does cmark read the
/// leading text node as a C-string and stop at the NUL, so `[^[` shows but the extracted email survives.
///
/// The rewrite has no embedded NUL; it emits `[^[` and marks the node "run-truncating". The bug (#168's
/// over-drop) was that consolidation dropped *every* following text node in the run before the autolink pass
/// ran, so a trailing email was discarded. The fix stops the consolidation run at the marked node and drops
/// its invisible tail only *after* the autolink pass — so `f@.f` in `[^[]]f@.f` is linked first.
@Suite("`[^[` footnote-collapse followed by an email autolink")
struct FootnoteCollapseTrailingAutolinkTests {

    /// The differential fuzzer's configuration for this finding: footnotes, GFM autolink, and cmark
    /// bug-compatibility all on. The collapse is gated on footnotes + `.cmarkBugCompatibility`.
    private static let flagOn: MarkdownDocument.ParseOptions =
        [.footnotes, .gfmAutolink, .cmarkBugCompatibility]

    /// The shipped configuration: footnotes and GFM autolink on, bug-compatibility deliberately off, so the
    /// collapse never fires and the bracket stays spec-correct literal text.
    private static let flagOff: MarkdownDocument.ParseOptions = [.footnotes, .gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsCollapseNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - The finding

    @Test("flag-ON: `[^[]]f@.f` collapses to `[^[` and the trailing email still autolinks")
    func collapseThenEmailFlagOn() throws {
        // Reconstructed text `[^[`, then the email split into a Link (Quirk M's empty `after` sibling stays).
        let ns = try nodes(in: "[^[]]f@.f", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "[^[", nil, "f@.f", ""])
        #expect(ns.compactMap(\.url) == ["mailto:f@.f"])
    }

    // MARK: - Control: the shipped deliverable stays spec-correct

    @Test("flag-OFF: `[^[]]f@.f` keeps the bracket literal and still autolinks the email")
    func collapseThenEmailFlagOff() throws {
        // No collapse (bug-compat off): the bracket is literal `[^[]]` and the email autolinks with no
        // trailing empty sibling (spec-correct clean tree).
        let ns = try nodes(in: "[^[]]f@.f", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "[^[]]", nil, "f@.f"])
        #expect(ns.compactMap(\.url) == ["mailto:f@.f"])
    }

    // MARK: - Guard: trailing plain text (no email) is still dropped by the truncation

    @Test("guard: flag-ON `x[^[]]y` still collapses to `x[^[`, dropping the plain trailing text")
    func collapseDropsPlainTrailingText() throws {
        // With no email in the tail, the invisible tail (`y`) is dropped and nothing autolinks.
        let ns = try nodes(in: "x[^[]]y", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "x[^["])
        #expect(ns.compactMap(\.url).isEmpty)
    }

    // MARK: - Guard: an email BEFORE the collapse still drops the plain text after it

    @Test("guard: flag-ON `f@.f[^[]]y` links the leading email and drops the plain trailing text")
    func emailBeforeCollapseDropsTrailingText() throws {
        // The email merges into the run-truncating node (`f@.f[^[`); the autolink split carves out the Link
        // and leaves the `[^[` residual as the run tail. The mark follows that tail, so the trailing `y`
        // (after the NUL) is still dropped - matching cmark's C-string truncation of the split's `after`
        // node. Quirk M's empty `before` sibling precedes the Link.
        let ns = try nodes(in: "f@.f[^[]]y", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "f@.f", "[^["])
        #expect(ns.compactMap(\.url) == ["mailto:f@.f"])
    }
}
