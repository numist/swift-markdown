/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Footnote reference under deep block-quote nesting")
struct DeepBlockQuoteFootnoteTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    /// A footnote reference 2,000 block quotes deep resolves to its definition, which moves to the
    /// document end.
    @Test func deepBlockQuoteFootnoteReferenceDoesNotOverflow() {
        let depth = 2_000
        let markdown = String(repeating: ">", count: depth) + " x[^a]\n\n[^a]: y\n"
        let (rootKinds, quotes, innermostKinds) = MarkdownDocument.withParsedDocument(markdown, options: Self.options) { doc in
            var rootKinds: [MarkdownNode.Kind] = []
            doc.root.children.forEach { rootKinds.append($0.kind) }
            var quotes = 0
            var innermostKinds: [MarkdownNode.Kind] = []
            var node = doc.root.firstChild
            while let current = node {
                guard case .blockQuote = current.kind else {
                    current.children.forEach { innermostKinds.append($0.kind) }
                    break
                }
                quotes += 1
                node = current.firstChild
            }
            return (rootKinds, quotes, innermostKinds)
        }

        #expect(rootKinds == [.blockQuote, .footnoteDefinition])
        #expect(quotes == 2_000)
        #expect(innermostKinds == [.text, .footnoteReference(index: 1)])
    }
}
