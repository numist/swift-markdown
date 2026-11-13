/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A list marker after 99 containers opened on the same line is paragraph text, while block quotes open on a line
/// past that count and list items nest without bound across lines. These trees are deeper than a document dump
/// reaches, so they are walked node by node.
struct ContainersOpenedOnLineTests {

    @Test func blockQuotesOnOneLineNest300Deep() {
        let document = Document(parsing: String(repeating: "> ", count: 300) + "x")

        var depth = 0
        var node: Markup? = document.child(at: 0)
        while let blockQuote = node as? BlockQuote {
            depth += 1
            #expect(blockQuote.childCount == 1)
            node = blockQuote.child(at: 0)
        }

        #expect(depth == 300)
        let paragraph = node as? Paragraph
        #expect(paragraph?.childCount == 1)
        #expect((paragraph?.child(at: 0) as? Text)?.string == "x")
    }

    /// Line `i` is `i` levels of two-space indentation and the item `- a<i>`, so each line continues every item
    /// above it and opens one more.
    @Test func listItemsOpenedOnePerLineNest150Deep() {
        let markdown = (0..<150).map { String(repeating: "  ", count: $0) + "- a\($0)" }.joined(separator: "\n")
        let document = Document(parsing: markdown)

        var depth = 0
        var node: Markup? = document.child(at: 0)
        while let list = node as? UnorderedList {
            #expect(list.childCount == 1)
            guard let item = list.child(at: 0) as? ListItem else { break }
            #expect(item.childCount == (depth == 149 ? 1 : 2))
            let paragraph = item.child(at: 0) as? Paragraph
            #expect((paragraph?.child(at: 0) as? Text)?.string == "a\(depth)")
            depth += 1
            node = item.child(at: 1)
        }

        #expect(depth == 150)
        #expect(node == nil)
    }
}
