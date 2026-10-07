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

/// A footnote-shaped bracket whose caret is backslash-escaped, `[\^…]`.
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
/// The spec-correct default processes the escape and keeps a single `]`.
@Suite("Backslash-escaped footnote caret `[\\^…]` reconstruction")
struct FootnoteEscapedCaretReconstructionTests {

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

    /// The shipped deliverable (bug-compat OFF) stays spec-correct: the escape is processed and the
    /// bracket keeps a single `]` (`[^x]`), never the doubled `]`.
    @Test("bug-compat OFF: `[\\^x]` stays spec-correct text `[^x]`")
    func escapedCaretStaysSpecCorrect() {
        let ns = nodes(in: "[\\^x]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["[^x]"])
    }

    /// The shipped deliverable (bug-compat OFF) stays spec-correct: the `!` is kept, the escape is
    /// processed, and the bracket keeps a single `]` (`![^x]`).
    @Test("bug-compat OFF: `![\\^x]` stays spec-correct text `![^x]`")
    func escapedCaretImageStaysSpecCorrect() {
        let ns = nodes(in: "![\\^x]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.compactMap(\.text) == ["![^x]"])
    }

    /// The shipped deliverable (bug-compat OFF) stays spec-correct: the escape is processed and the soft
    /// break is preserved, so the span stays `[^` + soft break + `x]`.
    @Test("bug-compat OFF: `[\\^\\nx]` keeps the soft break (`[^` + break + `x]`)")
    func escapedCaretCrossLineStaysSpecCorrect() {
        let ns = nodes(in: "[\\^\nx]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        #expect(ns.compactMap(\.text) == ["[^", "x]"])
    }
}
