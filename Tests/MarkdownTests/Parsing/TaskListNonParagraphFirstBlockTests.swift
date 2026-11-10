/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A list item whose first block is a list or thematic break is not a task list item, so `[x]` beginning a later
/// paragraph of the item is text (Task list items (extension)). A later line beginning with `2-` or `22` starts no list
/// item, so it is paragraph text too.
class TaskListNonParagraphFirstBlockTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    func testCheckboxAfterThematicBreak() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"[x] a\"", tree("- ***\n  [x] a"))
    }

    func testCheckboxAfterEmptyNestedItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"[x] a\"", tree("- -\n  [x] a"))
    }

    func testEmptyNestedItemThenTab() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x]\"", tree("- -\n  2- [x]\t"))
    }

    func testThematicBreakChild() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", tree("- ***\n  2- [x] a"))
    }

    func testEmptyNestedItemThenBlankLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", tree("- -\n\n  2- [x] a"))
    }

    func testEmptyNestedOrderedItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ OrderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", tree("- 1.\n  2- [x] a"))
    }

    func testEmptyNestedItemOnLaterLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", tree("-\n  -\n  2- [x] a"))
    }

    func testTwoDigitPrefixAfterEmptyNestedItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [x] a\"", tree("- -\n  22 [x] a"))
    }

    func testThematicBreakThenReferenceDefinition() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", tree("- ***\n  [a]: /u\n\n  2- [x] a"))
    }

    func testNestedListThenReferenceDefinition() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", tree("- -\n  [a]: /u\n\n  2- [x] a"))
    }
}
