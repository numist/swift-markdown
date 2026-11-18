/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// The space a block quote marker may be followed by takes one column of a tab (Tabs): all of a tab that starts at
// column 3 mod 4 (counting from 0), part of any other. Indentation after the marker counts from the column after that
// space (Block quotes).
class BlockQuoteTabColumnMatrixTests: XCTestCase {
    private static let listFence = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n"

    private enum Leaf {
        case none
        case paragraph(String)
        case code(String)
    }

    private func quotes(_ depth: Int, _ leaf: Leaf, head: String = listFence) -> String {
        var lines: [String] = []
        for level in 0..<depth {
            lines.append(String(repeating: " ", count: 3 * level) + "└─ BlockQuote")
        }
        let pad = String(repeating: " ", count: 3 * depth)
        switch leaf {
        case .none:
            break
        case .paragraph(let text):
            lines.append(pad + "└─ Paragraph")
            lines.append(pad + "   └─ Text \"\(text)\"")
        case .code(let literal):
            lines.append(pad + "└─ CodeBlock language: none")
            lines.append(pad + "   " + literal)
        }
        return head + lines.joined(separator: "\n")
    }

    private func assertTree(_ expected: String, _ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        let actual = Document(parsing: markdown).debugDescription(options: [])
        XCTAssertEqual(expected, actual, "input: \(markdown.debugDescription)", file: file, line: line)
    }

    func testTabBeforeMarkerAtEveryTabStop() {
        for k in 1...8 {
            assertTree(quotes(k + 1, .none), "- ```\n" + String(repeating: ">", count: k) + "\t>")
        }
    }

    func testSpacedMarkersThenTabBeforeMarker() {
        assertTree(quotes(3, .none), "- ```\n> >\t>")
        assertTree(quotes(4, .none), "- ```\n> > >\t>")
        assertTree(quotes(4, .none), "- ```\n>> >\t>")
        assertTree(quotes(3, .none), "- ```\n >>\t>")
        assertTree(quotes(3, .none), "- ```\n>  >\t>")
    }

    func testTabBeforeParagraphContent() {
        for k in 1...5 {
            assertTree(quotes(k, .paragraph("x")), "- ```\n" + String(repeating: ">", count: k) + "\tx")
        }
    }

    func testTabThenIndentedCodeAtEveryTabStop() {
        let leftover = [1: "  x", 2: " x", 3: "x", 4: "   x", 5: "  x"]
        for k in 1...5 {
            assertTree(quotes(k, .code(leftover[k]!)), "- ```\n" + String(repeating: ">", count: k) + "\t    x")
        }
    }

    func testTwoTabsBeforeMarker() {
        assertTree(quotes(1, .code("  >")), "- ```\n>\t\t>")
        assertTree(quotes(3, .code(">")), "- ```\n>>>\t\t>")
    }

    func testContinuationMarkerAfterPartiallyConsumedTab() {
        assertTree(quotes(2, .code("x"), head: "Document\n"), "> > ```\n>\t>x")
        assertTree(quotes(2, .code("x"), head: "Document\n"), "> > ```\n>\t> x")
        assertTree(quotes(2, .code("x"), head: "Document\n"), "> > ```\n>\t >x")
        assertTree("Document\n└─ BlockQuote\n   ├─ BlockQuote\n   │  └─ CodeBlock language: none\n\n   └─ CodeBlock language: none\n      >x", "> > ```\n>\t  >x")
        assertTree("Document\n└─ BlockQuote\n   └─ BlockQuote\n      └─ Paragraph\n         ├─ Text \"a\"\n         ├─ SoftBreak\n         └─ Text \"x\"", "> > a\n>\t> x")
    }

    func testContinuationMarkerAfterFullyConsumedTab() {
        assertTree(quotes(4, .code("x"), head: "Document\n"), ">>>> ```\n>>>\t>x")
    }

    func testFencedContentAfterFullyConsumedTab() {
        assertTree(quotes(3, .code("\tx"), head: "Document\n"), ">>> ```\n>>>\t\tx")
    }

    // Two columns of the tab follow the marker's optional space, fewer than the three the `1. ` item's content
    // needs (List items), so the item closes.
    func testItemContinuationIndentAfterQuoteMarker() {
        let closed = "Document\n└─ BlockQuote\n   ├─ OrderedList\n   │  └─ ListItem\n   │     └─ CodeBlock language: none\n\n   └─ Paragraph\n      └─ Text \"x\""
        assertTree(closed, "> 1. ```\n> \tx")
        assertTree(closed, "> 1. ```\n>\tx")
    }

    func testItemContinuationConsumesTabThenQuoteMarker() {
        let continued = "Document\n└─ BlockQuote\n   └─ UnorderedList\n      └─ ListItem\n         └─ BlockQuote\n            └─ CodeBlock language: none\n               x"
        assertTree(continued, "> - > ```\n>\t>x")
        assertTree(continued, "> - > ```\n> \t>x")
    }
}
