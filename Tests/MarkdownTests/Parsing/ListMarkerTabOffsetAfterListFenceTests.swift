/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A list marker after `>` TAB, on a line that closes a list item's open fence (so its tabs reach block
/// parsing unexpanded).
///
/// Ground truth is cmark-gfm, whose item content column counts the marker's leading indent in COLUMNS
/// (`marker_offset = parser->indent`, blocks.c `parse_list_marker`): the tab after `>` widens the
/// marker's offset to two columns, so the item's content starts at column 6 and a later `- ` indented
/// less than that opens a sibling item, not a sublist. The same lines without the fence line already
/// match. Spec-correct (CommonMark §2.2 tab stops), so both flag states must agree. Position-free
/// compare surface.
class ListMarkerTabOffsetAfterListFenceTests: XCTestCase {
    private static let listFence = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n"

    private func assertSurface(_ expected: String, _ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        for flag in [true, false] {
            var options = ParseOptions(rawValue: UInt(0x3e & 0b11011111))
            if flag { options.insert(.cmarkBugCompatibility) }
            let actual = Document(parsing: markdown, options: options).debugDescription(options: [])
            XCTAssertEqual(expected, actual, "cmarkBugCompatibility: \(flag), input: \(markdown.debugDescription)", file: file, line: line)
        }
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
