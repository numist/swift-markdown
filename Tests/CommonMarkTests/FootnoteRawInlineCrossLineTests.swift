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

/// An unresolved footnote-shaped bracket whose `]` lands on a later line than its
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
/// The shipped deliverable stays spec-correct: the interior parses as a real code span / raw HTML.
@Suite("Cross-line footnote raw-inline (code span / HTML) reconstruction")
struct FootnoteRawInlineCrossLineTests {

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

    /// The shipped deliverable (bug-compat off) stays spec-correct: the interior is a real code span, so
    /// the paragraph is `[^` + a code span + `]` (the span's single newline normalizes to one space).
    @Test("bug-compat OFF: code-span interior parses as a real code span")
    func codeSpanBugCompatOffStaysSpecCorrect() {
        let ns = nodes(in: "[^`\n`]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .codeInline(backtickCount: 1), .text])
        #expect(ns.compactMap(\.text) == ["[^", " ", "]"])
    }

    /// The shipped deliverable (bug-compat off) stays spec-correct: the interior is a real inline-HTML
    /// comment, so the paragraph is `[^` + the comment + `]`.
    @Test("bug-compat OFF: raw-HTML interior parses as a real inline-HTML comment")
    func rawHTMLBugCompatOffStaysSpecCorrect() {
        let ns = nodes(in: "[^<!--\n-->]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        #expect(ns.compactMap(\.text) == ["[^", "<!--\n-->", "]"])
    }

    /// The shipped deliverable (bug-compat off) stays spec-correct: the soft break and the real code span both
    /// survive, so the paragraph is `[^x` + a soft break + a code span + `]`, whereas cmark-gfm truncates the span to
    /// `` [^x\n`] ``.
    @Test("bug-compat OFF: mixed newlines keep the soft break and the code span")
    func mixedBareAndSwallowedNewlinesBugCompatOff() {
        let ns = nodes(in: "[^x\n`y\nz`]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .softBreak, .codeInline(backtickCount: 1), .text])
        #expect(ns.compactMap(\.text) == ["[^x", "y z", "]"])
    }
}
