/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class TaskListRetryItemWithChildTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        let options = ParseOptions(rawValue: UInt(0x0a & 0b11011111))
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testEmptyNestedItemThenTab() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x]\"", surface("- -\n  2- [x]\t"))
    }

    func testThematicBreakChild() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- ***\n  2- [x] a"))
    }

    func testEmptyNestedItemThenBlankLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- -\n\n  2- [x] a"))
    }

    func testEmptyNestedOrderedItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ OrderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- 1.\n  2- [x] a"))
    }

    func testEmptyNestedItemOnLaterLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("-\n  -\n  2- [x] a"))
    }

    func testDigitWildcardAfterEmptyNestedItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [x] a\"", surface("- -\n  22 [x] a"))
    }

    /// Flag-off (spec-correct): the item's first block is a thematic break, not a paragraph (GFM task list
    /// items), so the item has no checkbox and `2- [x] a` stays paragraph text, where cmark's later-line
    /// checkbox retry checks the item once the dropped definition closes the break.
    func testThematicBreakThenDroppedReferenceDefinitionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- ***\n  [a]: /u\n\n  2- [x] a"))
    }

    /// Flag-off (spec-correct): the item's first block is a list, not a paragraph (GFM task list items), so
    /// the item has no checkbox and `2- [x] a` stays paragraph text, where cmark's later-line checkbox
    /// retry checks the item once the dropped definition closes the list.
    func testNestedListThenDroppedReferenceDefinitionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- -\n  [a]: /u\n\n  2- [x] a"))
    }
}
