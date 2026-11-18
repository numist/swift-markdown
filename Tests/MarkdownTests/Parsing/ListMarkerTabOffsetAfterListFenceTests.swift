/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// After `>`, the tab's first column is the block quote marker's optional space and its other two indent the list
// marker (Tabs), so they count toward the item's content column (List items).
class ListMarkerTabOffsetAfterListFenceTests: XCTestCase {
    private static let listFence = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n"

    private func assertTree(_ expected: String, _ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        let actual = Document(parsing: markdown).debugDescription(options: [])
        XCTAssertEqual(expected, actual, "input: \(markdown.debugDescription)", file: file, line: line)
    }

    func testBulletAfterQuoteTabShortOfContentColumnIsSibling() {
        let siblings = Self.listFence + "└─ BlockQuote\n   └─ UnorderedList\n      ├─ ListItem\n      │  └─ Paragraph\n      │     └─ Text \"x\"\n      └─ ListItem\n         └─ Paragraph\n            └─ Text \"y\""
        assertTree(siblings, "- ```\n>\t- x\n>    - y")
    }

    // Four columns of indentation fall one short of the item's content column (2 + 3 = 5) and are too many to open a
    // list item, so the line is a lazy continuation of `x`'s paragraph.
    func testOrderedAfterQuoteTabShortOfContentColumnIsLazy() {
        let lazy = Self.listFence + "└─ BlockQuote\n   └─ OrderedList\n      └─ ListItem\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            └─ Text \"1. y\""
        assertTree(lazy, "- ```\n>\t1. x\n>     1. y")
    }

    func testBulletAtContentColumnNests() {
        let nested = Self.listFence + "└─ BlockQuote\n   └─ UnorderedList\n      └─ ListItem\n         ├─ Paragraph\n         │  └─ Text \"x\"\n         └─ UnorderedList\n            └─ ListItem\n               └─ Paragraph\n                  └─ Text \"y\""
        assertTree(nested, "- ```\n>\t- x\n>     - y")
    }
}
