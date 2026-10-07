/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class TaskListChildlessItemAdvanceTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the NUL is an ordinary U+FFFD in the paragraph text, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testNULWildcardThenCheckboxFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x]\"", surface("+\n  2\u{0} [x] "))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and `[X]` stays paragraph text, where cmark's later-line
    /// checkbox retry checks the item and drops the advanced bytes.
    func testNULWildcardThenUppercaseCheckboxAndContentFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [X] a\"", surface("+\n  2\u{0} [X] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the NUL is one ordinary U+FFFD, where cmark's later-line
    /// checkbox retry checks the item and orphans two of the NUL's replacement bytes.
    func testNULWildcardAfterTwoDigitsFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22\u{FFFD} [x] a\"", surface("+\n  22\u{0} [x] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the NUL is one ordinary U+FFFD, where cmark's later-line
    /// checkbox retry checks the item and orphans two of the NUL's replacement bytes.
    func testNULWildcardAfterPartiallyConsumedTabFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\"", surface("+\n\t2\u{0} [x] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and both NULs are ordinary U+FFFDs, where cmark's later-line
    /// checkbox retry checks the item and drops the advanced bytes.
    func testLaterNULIsReplacedFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\u{FFFD}b\"", surface("+\n  2\u{0} [x] a\u{0}b"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the continuation line joins it with a soft break, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testContinuationAfterDigitLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{FFFD} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"", surface("+\n  2\u{0} [x] a\n  b"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line is an ordinary header row for the delimiter row
    /// below, where cmark's later-line checkbox retry checks the item, leaving orphaned bytes that stop its
    /// header scan.
    func testNULLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body\n            └─ Row\n               ├─ Cell\n               │  └─ Text \"c\"\n               └─ Cell\n                  └─ Text \"d\"", surface("+\n  2\u{0} [x] a|b\n  -|-\n  c|d"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line is an ordinary header row for the delimiter row
    /// below, where cmark's later-line checkbox retry checks the item, leaving an orphaned byte that stops
    /// its header scan.
    func testMultiByteLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"22\u{E9} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  22\u{E9} [x] a|b\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line is an ordinary header row for the delimiter row
    /// below, where cmark's later-line checkbox retry checks the item, leaving orphaned bytes that stop its
    /// header scan.
    func testFourByteLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{1F600} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  2\u{1F600} [x] a|b\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the table's first header cell keeps the whole `22 [x] a`,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testOrphanFreeLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"22 [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  22 [x] a|b\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and its last line heads a table under it, where cmark's
    /// later-line checkbox retry checks the item, leaving orphaned bytes that stop its header scan.
    func testDigitLedParagraphOpensTableOnLaterLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ Paragraph\n      │  └─ Text \"2\u{FFFD} [x] a\"\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"b\"\n         │  └─ Cell\n         │     └─ Text \"c\"\n         └─ Body", surface("+\n  2\u{0} [x] a\n  b|c\n  -|-"))
    }

    /// Without a checkbox the scan doesn't match, nothing is advanced, and the NUL is an ordinary U+FFFD.
    func testNULHeaderWithoutCheckboxOpensTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  2\u{0} a|b\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line stays paragraph text whole, where cmark's
    /// later-line checkbox retry checks the item and drops the advanced bytes.
    func testPartiallyConsumedTabFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2x [x]\"", surface("+\n\t 2x [x] "))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line stays paragraph text whole, where cmark's
    /// later-line checkbox retry checks the item and drops the advanced bytes.
    func testPartiallyConsumedTabBeforeDigitRunFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [x]\"", surface("+\n\t 22 [x] "))
    }

    // MARK: Guards (equal to the reference before this fix)

    func testNULAfterWildcardDoesNotMatch() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}x [x] a\"", surface("+\n  2\u{0}x [x] a"))
    }

    func testDoubleNULWildcardDoesNotMatch() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}\u{FFFD} [x] a\"", surface("+\n  2\u{0}\u{0} [x] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the `é` stays intact, where cmark's later-line checkbox
    /// retry checks the item and orphans the `é`'s continuation byte.
    func testMultiByteWildcardFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22\u{E9} [x] a\"", surface("+\n  22\u{E9} [x] a"))
    }

    /// Flag-off (spec-correct): no checkbox, and the NUL is an ordinary U+FFFD in the paragraph text.
    func testFlagOffNoCheckbox() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\"",
            Document(parsing: "+\n  2\u{0} [x] a").debugDescription(options: []))
    }
}
