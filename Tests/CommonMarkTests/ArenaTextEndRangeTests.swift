/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges of text on a paragraph continuation line indented to its list item's content column.
@Suite("Text source range on an indented continuation line")
struct ArenaTextEndRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart]

    /// DFS-collect every text node's literal and source range.
    private func textNodes(in src: String) -> [(literal: String?, range: Range<Pos>?)] {
        var out: [(literal: String?, range: Range<Pos>?)] = []
        MarkdownDocument.withParsedDocument(src, options: Self.specOptions) { doc in
            collectText(doc.root, into: &out)
        }
        return out
    }

    @Test("text on an indented continuation line starts at its own source column")
    func indentedContinuationKeepsSourceColumn() throws {
        let texts = textNodes(in: " - b\n   c\n  d")
        try #require(texts.count == 3, "expected b / c / d text nodes")
        try #require(texts[1].literal == "c", "expected a plain `c` text node, got \(String(describing: texts[1].literal))")

        #expect(texts[1].range?.lowerBound == Pos(line: 2, column: 4))
        #expect(texts[1].range?.upperBound == Pos(line: 2, column: 5))
    }
}

/// Depth-first: every text node's literal and source range.
private func collectText(
    _ node: borrowing MarkdownNode,
    into out: inout [(literal: String?, range: Range<MarkdownNode.SourcePosition>?)]
) {
    if node.kind == .text {
        out.append((node.literal(), node.sourceRange))
    }
    node.children.forEach { child in
        collectText(child, into: &out)
    }
}
