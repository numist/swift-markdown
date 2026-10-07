/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Appends every node's kind and literal text to `out`, in depth-first order.
private func dfsKindText(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsKindText(child, into: &out)
    }
}

/// Code spans and raw HTML bind more tightly than the brackets in link text (Links), and likewise than a
/// footnote-shaped bracket: one enclosing a code span or raw HTML that spans a line ending is literal text
/// around it.
@Suite("Footnote-shaped bracket around a code span or raw HTML spanning a line ending")
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

    @Test("code span interior parses as a code span")
    func codeSpanInteriorParsesAsCodeSpan() {
        let ns = nodes(in: "[^`\n`]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .codeInline(backtickCount: 1), .text])
        #expect(ns.compactMap(\.text) == ["[^", " ", "]"])
    }

    @Test("raw HTML interior parses as an HTML comment")
    func rawHTMLInteriorParsesAsRawHTML() {
        let ns = nodes(in: "[^<!--\n-->]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        #expect(ns.compactMap(\.text) == ["[^", "<!--\n-->", "]"])
    }

    @Test("a soft line break before a code span spanning a line ending keeps both")
    func softBreakBeforeCrossLineCodeSpan() {
        let ns = nodes(in: "[^x\n`y\nz`]", options: [.sourcePosition, .footnotes])
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .softBreak, .codeInline(backtickCount: 1), .text])
        #expect(ns.compactMap(\.text) == ["[^x", "y z", "]"])
    }
}
