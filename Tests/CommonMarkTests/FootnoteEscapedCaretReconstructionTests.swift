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

/// A footnotes bug-compatibility divergence the differential fuzzer found against cmark-gfm (via
/// swift-markdown@main): a footnote-shaped bracket whose caret is backslash-escaped, `[\^x]`.
///
/// cmark still treats the bracket as a footnote reference — the text node after `[` is the escaped `^` —
/// but it measures the reference-label length in *columns* from the `[` (counting the backslash) while
/// reading the label bytes from just past the `^`. The extra backslash column runs the read one byte
/// past the label into the closing `]`, so the unresolved reference reconstructs as `[^` + captured
/// bytes + `]`, doubling the `]`: `[\^x]` becomes the text `[^x]]`. The spec-correct default processes
/// the escape and keeps a single `]` (`[^x]`), so this is reproduced only under `.cmarkBugCompatibility`.
@Suite("Backslash-escaped footnote caret `[\\^x]` reconstruction")
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
}
