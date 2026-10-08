/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Appends every node's kind and literal text to `out`, in depth-first order.
internal func dfsKindsAndText(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsKindsAndText(child, into: &out)
    }
}

/// Spaces at the end of a line before a soft line break are removed (Soft line breaks), so a trailing
/// space after a link, emphasis or inline code produces no text node.
@Suite("Trailing space before a soft line break")
struct EmptyTextBeforeSoftBreakTests {

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The `(kind, text)` of every node, in depth-first order.
    private func nodes(in src: String) -> [(kind: MarkdownNode.Kind, text: String?)] {
        MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, text: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?)] = []
            dfsKindsAndText(doc.root, into: &out)
            return out
        }
    }

    @Test("emphasis + trailing space + soft line break: no empty text node")
    func emphasis() {
        let ns = nodes(in: "*x* \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .softBreak, .text])
        #expect(ns.compactMap(\.text) == ["x", "y"])
    }

    @Test("inline code + trailing space + soft line break: no empty text node")
    func inlineCode() {
        let ns = nodes(in: "`c` \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1), .softBreak, .text])
        // `literal()` also returns inline code content.
        #expect(ns.compactMap(\.text) == ["c", "y"])
    }

    @Test("link + trailing space + soft line break: no empty text node")
    func link() {
        let ns = nodes(in: "[foo] \n[]\n\n[foo]: /url \"title\"")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .softBreak, .text])
        #expect(ns.compactMap(\.text) == ["foo", "[]"])
    }
}
