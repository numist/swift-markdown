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
// noncopyable-borrow rules (see FootnoteEscapedCaretReconstructionTests.dfsKindText).
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
/// swift-markdown@main): an unresolved footnote-shaped bracket whose `]` lands on a later line than its
/// `[`, where the spanning newline is swallowed by a raw-scan inline (a code span or raw HTML) rather
/// than being a bare soft break.
///
/// cmark resets its per-line column cursor at such a newline (`adjust_subj_node_newlines`, `src/inlines.c`)
/// ONLY when `CMARK_OPT_SOURCEPOS` is on — unlike `handle_newline` (soft/space breaks), which always
/// resets. The reference (swift-markdown@main) leaves `CMARK_OPT_SOURCEPOS` off when
/// `.disableSourcePosOpts` is set, so the swallowed newline does NOT reset the cursor and stays part of
/// the raw byte capture cmark makes for the unresolved reference's text: `` [^`\n`] `` reconstructs
/// verbatim rather than collapsing to `[^]`. With source positions on, the same newline resets the
/// cursor and the label underflows, collapsing to `[^]`.
///
/// The rewrite always tracks positions (ranges are read off the AST regardless of the flag), so it
/// carries a separate `.cmarkSourcePositionsDisabled` signal — forwarded by the Markdown layer only
/// alongside `.cmarkBugCompatibility` when `.disableSourcePosOpts` is set — to reproduce this
/// source-positions-off content quirk. The shipped deliverable (bug-compat off) never sets it and stays
/// spec-correct: the interior parses as a real code span / raw HTML.
@Suite("Cross-line footnote raw-inline (code span / HTML) reconstruction")
struct FootnoteRawInlineCrossLineTests {

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

    /// Bug-compat ON with source positions OFF (the differential target): the code-span newline does not
    /// reset the cursor, so the interior stays in the raw byte capture — `` [^`\n`] `` reconstructs as one
    /// verbatim text node, backticks and newline included.
    @Test("bug-compat ON, sourcepos OFF: code-span interior kept verbatim (`` [^`\\n`] ``)")
    func codeSpanSourcePosOffKeepsRawInterior() throws {
        let ns = try nodes(
            in: "[^`\n`]",
            options: [.sourcePosition, .cmarkBugCompatibility, .cmarkSourcePositionsDisabled, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^`\n`]"])
    }

    /// Bug-compat ON with source positions ON: cmark's `adjust_subj_node_newlines` runs, so the code-span
    /// newline resets the per-line column and the captured label underflows to empty, collapsing the whole
    /// span to `[^]`. The `.cmarkSourcePositionsDisabled` fix must NOT change this regime.
    @Test("bug-compat ON, sourcepos ON: code-span span collapses to `[^]`")
    func codeSpanSourcePosOnCollapses() throws {
        let ns = try nodes(
            in: "[^`\n`]",
            options: [.sourcePosition, .cmarkBugCompatibility, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^]"])
    }

    /// The shipped deliverable (bug-compat off) stays spec-correct: the interior is a real code span, so
    /// the paragraph is `[^` + a code span + `]` (the span's single newline normalizes to one space).
    @Test("bug-compat OFF: code-span interior parses as a real code span")
    func codeSpanBugCompatOffStaysSpecCorrect() throws {
        let ns = try nodes(in: "[^`\n`]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .codeInline(backtickCount: 1), .text])
        #expect(ns.compactMap(\.text) == ["[^", " ", "]"])
    }

    /// The same quirk for the other raw-scan inline, raw HTML: cmark gates its cursor reset on
    /// `CMARK_OPT_SOURCEPOS` for inline HTML too (`src/inlines.c` `handle_pointy_brace`), so with source
    /// positions off a comment's interior newline stays in the raw capture — `[^<!--\n-->]` reconstructs
    /// verbatim.
    @Test("bug-compat ON, sourcepos OFF: raw-HTML interior kept verbatim (`[^<!--\\n-->]`)")
    func rawHTMLSourcePosOffKeepsRawInterior() throws {
        let ns = try nodes(
            in: "[^<!--\n-->]",
            options: [.sourcePosition, .cmarkBugCompatibility, .cmarkSourcePositionsDisabled, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^<!--\n-->]"])
    }

    /// The shipped deliverable (bug-compat off) stays spec-correct: the interior is a real inline-HTML
    /// comment, so the paragraph is `[^` + the comment + `]`.
    @Test("bug-compat OFF: raw-HTML interior parses as a real inline-HTML comment")
    func rawHTMLBugCompatOffStaysSpecCorrect() throws {
        let ns = try nodes(in: "[^<!--\n-->]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        #expect(ns.compactMap(\.text) == ["[^", "<!--\n-->", "]"])
    }

    /// Raw HTML, bug-compat ON with source positions ON: cmark's `adjust_subj_node_newlines` runs, so the
    /// comment's newline resets the per-line column; the captured label reads just the one byte past the
    /// `^` (`<`), reconstructing `[^<]`. The `.cmarkSourcePositionsDisabled` fix must NOT change this.
    @Test("bug-compat ON, sourcepos ON: raw-HTML span reconstructs to `[^<]`")
    func rawHTMLSourcePosOnResetsColumn() throws {
        let ns = try nodes(
            in: "[^<!--\n-->]",
            options: [.sourcePosition, .cmarkBugCompatibility, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^<]"])
    }

    /// Mixed newlines, bug-compat ON with source positions OFF: a bare soft break (`\n` after `x`) resets
    /// the per-line column, but the code-span newline (inside `` `y\nz` ``) does not — so cmark's raw
    /// capture starts after the soft break and runs verbatim across the code-span newline. Guards the
    /// content-offset alignment between recording (parse cursor) and measurement
    /// (`footnoteCapturedLabelLength`) when both kinds of newline occur in one span: `` [^x\n`y\nz`] `` ->
    /// `` [^x\n`] ``.
    @Test("bug-compat ON, sourcepos OFF: bare break resets, code-span break does not (`` [^x\\n`] ``)")
    func mixedBareAndSwallowedNewlines() throws {
        let ns = try nodes(
            in: "[^x\n`y\nz`]",
            options: [.sourcePosition, .cmarkBugCompatibility, .cmarkSourcePositionsDisabled, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^x\n`]"])
    }
}
