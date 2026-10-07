/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// The later-line tasklist retry does not fire while the item's last child is a list or a thematic break.
///
/// Ground truth is cmark-gfm (flag-ON). cmark's `open_tasklist_item` retry (see
/// `TaskListDigitPrefixCheckboxTests`) runs only when the item is the line's deepest matched container. cmark
/// keeps a list or thematic break open (and matching every line) until a later sibling follows it, so while
/// one is the item's last child a later `2- [x]` line is plain paragraph text and the item gets no checkbox.
/// A reference-definition-only paragraph that followed it still closed it, even though that paragraph is
/// then dropped, so the retry fires again. Position-free compare surface.
class TaskListRetryItemWithChildTests: XCTestCase {
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var options = ParseOptions(rawValue: UInt(0x0a & 0b11011111))
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testEmptyNestedItemThenTab() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x]\"", surface("- -\n  2- [x]\t"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x]\"", surface("- -\n  2- [x]\t", cmarkBugCompatible: false))
    }

    func testThematicBreakChild() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- ***\n  2- [x] a"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- ***\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testEmptyNestedItemThenBlankLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- -\n\n  2- [x] a"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- -\n\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testEmptyNestedOrderedItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ OrderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- 1.\n  2- [x] a"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ OrderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- 1.\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testEmptyNestedItemOnLaterLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("-\n  -\n  2- [x] a"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("-\n  -\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testDigitWildcardAfterEmptyNestedItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [x] a\"", surface("- -\n  22 [x] a"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [x] a\"", surface("- -\n  22 [x] a", cmarkBugCompatible: false))
    }

    func testThematicBreakClosedByDroppedReferenceDefinition() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"[x] a\"", surface("- ***\n  [a]: /u\n\n  2- [x] a"))
    }

    /// Flag-off (spec-correct): the item's first block is a thematic break, not a paragraph (GFM task list
    /// items), so the item has no checkbox and `2- [x] a` stays paragraph text, where cmark's later-line
    /// checkbox retry checks the item once the dropped definition closes the break.
    func testThematicBreakThenDroppedReferenceDefinitionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ ThematicBreak\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- ***\n  [a]: /u\n\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testNestedListClosedByDroppedReferenceDefinition() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"[x] a\"", surface("- -\n  [a]: /u\n\n  2- [x] a"))
    }

    /// Flag-off (spec-correct): the item's first block is a list, not a paragraph (GFM task list items), so
    /// the item has no checkbox and `2- [x] a` stays paragraph text, where cmark's later-line checkbox
    /// retry checks the item once the dropped definition closes the list.
    func testNestedListThenDroppedReferenceDefinitionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ UnorderedList\n      │  └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- -\n  [a]: /u\n\n  2- [x] a", cmarkBugCompatible: false))
    }
}
