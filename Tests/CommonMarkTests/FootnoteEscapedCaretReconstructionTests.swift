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
// noncopyable-borrow rules (see FootnoteNestedBracketLinkTests.dfsKindText).
private func dfsKindText(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsKindText(child, into: &out)
    }
}

/// A family of footnotes bug-compatibility divergences the differential fuzzer found against cmark-gfm
/// (via swift-markdown@main): a footnote-shaped bracket whose caret is backslash-escaped, `[\^…]`.
///
/// cmark still treats the bracket as a footnote reference — the text node after `[` is the escaped `^` —
/// but it measures the reference-label length in *columns* from the opener's start (the `[`, or the `!`
/// of an image opener), spanning the backslash, while reading the label bytes from just past the `^`.
/// Counting the backslash column runs the read one byte past the label. The unresolved reference then
/// reconstructs as `[^` + captured bytes + `]`:
///   - a `[` opener captures the closing `]`, doubling it: `[\^x]` -> `[^x]]`;
///   - an image `![` opener starts one column further left, over-reading a second byte into the
///     paragraph's trailing newline and dropping the `!`: `![\^x]` -> `[^x]\n]`;
///   - a cross-line span resets the per-line column at the soft break, underflowing to an empty label:
///     `[\^\nx]` -> `[^]`.
/// The spec-correct default processes the escape and keeps a single `]`, so each is reproduced only
/// under `.cmarkBugCompatibility`.
@Suite("Backslash-escaped footnote caret `[\\^…]` reconstruction")
struct FootnoteEscapedCaretReconstructionTests {

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

    /// Bug-compat ON reproduces cmark's over-read: `[\^x]` -> the text `[^x]]` with a doubled `]`.
    @Test("bug-compat ON: `[\\^x]` reconstructs to the text `[^x]]`")
    func escapedCaretDoublesCloseBracket() throws {
        let ns = try nodes(in: "[\\^x]", options: [.sourcePosition, .cmarkBugCompatibility, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^x]]"])
    }

    /// The shipped deliverable (bug-compat OFF) stays spec-correct: the escape is processed and the
    /// bracket keeps a single `]` (`[^x]`), never the doubled `]`.
    @Test("bug-compat OFF: `[\\^x]` stays spec-correct text `[^x]`")
    func escapedCaretStaysSpecCorrect() throws {
        let ns = try nodes(in: "[\\^x]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^x]"])
    }

    /// Bug-compat ON, image opener: the `![` starts one column left of the `[`, so cmark over-reads a
    /// second byte past the `]` into the paragraph's trailing newline and drops the `!`: `![\^x]` ->
    /// the text `[^x]\n]`.
    @Test("bug-compat ON: `![\\^x]` reconstructs to the text `[^x]\\n]`")
    func escapedCaretImageDropsBangAndOverReadsNewline() throws {
        let ns = try nodes(in: "![\\^x]", options: [.sourcePosition, .cmarkBugCompatibility, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^x]\n]"])
    }

    /// The shipped deliverable (bug-compat OFF) stays spec-correct: the `!` is kept, the escape is
    /// processed, and the bracket keeps a single `]` (`![^x]`).
    @Test("bug-compat OFF: `![\\^x]` stays spec-correct text `![^x]`")
    func escapedCaretImageStaysSpecCorrect() throws {
        let ns = try nodes(in: "![\\^x]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["![^x]"])
    }

    /// Bug-compat ON, cross-line: the soft break resets the per-line column, underflowing the label
    /// length so the whole span collapses to the text `[^]` — the inner content and the soft break are
    /// dropped: `[\^\nx]` -> `[^]`.
    @Test("bug-compat ON: `[\\^\\nx]` collapses to the text `[^]`")
    func escapedCaretCrossLineCollapses() throws {
        let ns = try nodes(in: "[\\^\nx]", options: [.sourcePosition, .cmarkBugCompatibility, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^]"])
    }

    /// The shipped deliverable (bug-compat OFF) stays spec-correct: the escape is processed and the soft
    /// break is preserved, so the span stays `[^` + soft break + `x]`.
    @Test("bug-compat OFF: `[\\^\\nx]` keeps the soft break (`[^` + break + `x]`)")
    func escapedCaretCrossLineStaysSpecCorrect() throws {
        let ns = try nodes(in: "[\\^\nx]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        #expect(ns.compactMap(\.text) == ["[^", "x]"])
    }
}
