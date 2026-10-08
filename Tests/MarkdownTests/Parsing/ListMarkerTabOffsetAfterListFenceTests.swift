/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A list item in a block quote whose marker follows `>` TAB, on a line that ends a list item holding an
/// unclosed fenced code block. The tab counts in columns (Tabs): one column is the block quote marker's
/// optional space and the other two indent the list marker, so they count toward the item's content column
/// (List items).
class ListMarkerTabOffsetAfterListFenceTests: XCTestCase {
    private static let listFence = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n"

    private func assertSurface(_ expected: String, _ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        let options = ParseOptions(rawValue: UInt(0x3e & 0b11011111))
        let actual = Document(parsing: markdown, options: options).debugDescription(options: [])
        XCTAssertEqual(expected, actual, "input: \(markdown.debugDescription)", file: file, line: line)
    }

    func testBulletAfterQuoteTabIsSiblingOfShallowerBullet() {
        let siblings = Self.listFence + "└─ BlockQuote\n   └─ UnorderedList\n      ├─ ListItem\n      │  └─ Paragraph\n      │     └─ Text \"x\"\n      └─ ListItem\n         └─ Paragraph\n            └─ Text \"y\""
        assertSurface(siblings, "- ```\n>\t- x\n>    - y")
    }

    /// Four columns in, one short of the ordered item's content column (2 + 3 = 5): the item does not
    /// continue, and a four-column indent can't open a marker at the quote, so the line is a lazy
    /// continuation of `x`'s paragraph.
    func testOrderedAfterQuoteTabShortOfContentColumnIsLazy() {
        let lazy = Self.listFence + "└─ BlockQuote\n   └─ OrderedList\n      └─ ListItem\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            └─ Text \"1. y\""
        assertSurface(lazy, "- ```\n>\t1. x\n>     1. y")
    }

    /// Indented to the item's content column: the second marker nests.
    func testBulletAtContentColumnNests() {
        let nested = Self.listFence + "└─ BlockQuote\n   └─ UnorderedList\n      └─ ListItem\n         ├─ Paragraph\n         │  └─ Text \"x\"\n         └─ UnorderedList\n            └─ ListItem\n               └─ Paragraph\n                  └─ Text \"y\""
        assertSurface(nested, "- ```\n>\t- x\n>     - y")
    }
}
