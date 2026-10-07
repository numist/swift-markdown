/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Where a childless item's later-line checkbox leaves its paragraph content to start.
///
/// Ground truth is cmark-gfm (flag-ON). When `open_tasklist_item` matches on a childless item's later line
/// (see `TaskListDigitPrefixCheckboxTests`), it advances exactly 3 bytes from the parse offset
/// (`S_advance_offset` with `columns == false`). Those bytes are counted in cmark's own line buffer. There,
/// a NUL is already the 3-byte U+FFFD, so the advance can stop inside it, and each orphaned continuation
/// byte then reads back as one U+FFFD. A tab counts as one byte, even one the item's indent only partly
/// consumed. Position-free compare surface.
class TaskListChildlessItemAdvanceTests: XCTestCase {
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        Document(parsing: markdown, options: cmarkBugCompatible ? [.cmarkBugCompatibility] : []).debugDescription(options: [])
    }

    private func taskItem(checked: Bool, text: String) -> String {
        "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [\(checked ? "x" : " ")]\n      └─ Paragraph\n         └─ Text \"\(text)\""
    }

    // MARK: NUL wildcard: the advance stops inside its U+FFFD

    func testNULWildcardThenCheckbox() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x]"), surface("+\n  2\u{0} [x] "))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the NUL is an ordinary U+FFFD in the paragraph text, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testNULWildcardThenCheckboxFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x]\"", surface("+\n  2\u{0} [x] ", cmarkBugCompatible: false))
    }

    func testNULWildcardThenUppercaseCheckboxAndContent() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [X] a"), surface("+\n  2\u{0} [X] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and `[X]` stays paragraph text, where cmark's later-line
    /// checkbox retry checks the item and drops the advanced bytes.
    func testNULWildcardThenUppercaseCheckboxAndContentFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [X] a\"", surface("+\n  2\u{0} [X] a", cmarkBugCompatible: false))
    }

    func testNULWildcardThenCheckboxAndContent() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x] a"), surface("+\n  2\u{0} [x] a"))
    }

    /// Two digits put the NUL at the advance's last byte, orphaning two of its three bytes.
    func testNULWildcardAfterTwoDigitsOrphansTwoBytes() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD}\u{FFFD} [x] a"), surface("+\n  22\u{0} [x] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the NUL is one ordinary U+FFFD, where cmark's later-line
    /// checkbox retry checks the item and orphans two of the NUL's replacement bytes.
    func testNULWildcardAfterTwoDigitsFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22\u{FFFD} [x] a\"", surface("+\n  22\u{0} [x] a", cmarkBugCompatible: false))
    }

    /// A partly consumed tab counts one byte, so the NUL is the advance's last byte.
    func testNULWildcardAfterPartiallyConsumedTabOrphansTwoBytes() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD}\u{FFFD} [x] a"), surface("+\n\t2\u{0} [x] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the NUL is one ordinary U+FFFD, where cmark's later-line
    /// checkbox retry checks the item and orphans two of the NUL's replacement bytes.
    func testNULWildcardAfterPartiallyConsumedTabFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\"", surface("+\n\t2\u{0} [x] a", cmarkBugCompatible: false))
    }

    func testLaterNULOnOrphanLineIsReplaced() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x] a\u{FFFD}b"), surface("+\n  2\u{0} [x] a\u{0}b"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and both NULs are ordinary U+FFFDs, where cmark's later-line
    /// checkbox retry checks the item and drops the advanced bytes.
    func testLaterNULIsReplacedFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\u{FFFD}b\"", surface("+\n  2\u{0} [x] a\u{0}b", cmarkBugCompatible: false))
    }

    func testContinuationAfterOrphanLine() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{FFFD} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"",
            surface("+\n  2\u{0} [x] a\n  b"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the continuation line joins it with a soft break, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testContinuationAfterDigitLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{FFFD} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"", surface("+\n  2\u{0} [x] a\n  b", cmarkBugCompatible: false))
    }

    private func paragraphItem(_ lines: [String]) -> String {
        "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n"
            + lines.enumerated().map { index, line in
                "         \(index == lines.count - 1 ? "└" : "├")─ Text \"\(line)\""
            }.joined(separator: "\n         ├─ SoftBreak\n")
    }

    // MARK: An orphan-led paragraph never opens a table

    // cmark's table header row is parsed from the paragraph's whole raw content, which starts with the
    // orphaned byte(s); its UTF-8 `scan_table_cell` rejects a lone continuation byte, so no header row ever
    // parses.

    func testNULOrphanLineDoesNotOpenTable() {
        XCTAssertEqual(paragraphItem(["\u{FFFD} [x] a|b", "-|-", "c|d"]), surface("+\n  2\u{0} [x] a|b\n  -|-\n  c|d"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line is an ordinary header row for the delimiter row
    /// below, where cmark's later-line checkbox retry checks the item, leaving orphaned bytes that stop its
    /// header scan.
    func testNULLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body\n            └─ Row\n               ├─ Cell\n               │  └─ Text \"c\"\n               └─ Cell\n                  └─ Text \"d\"", surface("+\n  2\u{0} [x] a|b\n  -|-\n  c|d", cmarkBugCompatible: false))
    }

    func testMultiByteOrphanLineDoesNotOpenTable() {
        XCTAssertEqual(paragraphItem(["\u{FFFD} [x] a|b", "-|-"]), surface("+\n  22\u{E9} [x] a|b\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line is an ordinary header row for the delimiter row
    /// below, where cmark's later-line checkbox retry checks the item, leaving an orphaned byte that stops
    /// its header scan.
    func testMultiByteLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"22\u{E9} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  22\u{E9} [x] a|b\n  -|-", cmarkBugCompatible: false))
    }

    func testFourByteOrphanLineDoesNotOpenTable() {
        XCTAssertEqual(paragraphItem(["\u{FFFD}\u{FFFD} [x] a|b", "-|-"]), surface("+\n  2\u{1F600} [x] a|b\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line is an ordinary header row for the delimiter row
    /// below, where cmark's later-line checkbox retry checks the item, leaving orphaned bytes that stop its
    /// header scan.
    func testFourByteLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{1F600} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  2\u{1F600} [x] a|b\n  -|-", cmarkBugCompatible: false))
    }

    /// Control: an advance that ends on a scalar boundary leaves nothing orphaned, so the table opens.
    func testOrphanFreeLineOpensTable() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"[x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body",
            surface("+\n  22 [x] a|b\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the table's first header cell keeps the whole `22 [x] a`,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testOrphanFreeLineOpensTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"22 [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  22 [x] a|b\n  -|-", cmarkBugCompatible: false))
    }

    func testOrphanLedParagraphDoesNotOpenTableOnLaterLine() {
        XCTAssertEqual(paragraphItem(["\u{FFFD} [x] a", "b|c", "-|-"]), surface("+\n  2\u{0} [x] a\n  b|c\n  -|-"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and its last line heads a table under it, where cmark's
    /// later-line checkbox retry checks the item, leaving orphaned bytes that stop its header scan.
    func testDigitLedParagraphOpensTableOnLaterLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ Paragraph\n      │  └─ Text \"2\u{FFFD} [x] a\"\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"b\"\n         │  └─ Cell\n         │     └─ Text \"c\"\n         └─ Body", surface("+\n  2\u{0} [x] a\n  b|c\n  -|-", cmarkBugCompatible: false))
    }

    /// Without a checkbox the scan doesn't match, nothing is advanced, and the NUL is an ordinary U+FFFD.
    func testNULHeaderWithoutCheckboxOpensTable() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body",
            surface("+\n  2\u{0} a|b\n  -|-"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  2\u{0} a|b\n  -|-", cmarkBugCompatible: false))
    }

    // MARK: Tabs count one byte

    /// The item's indent consumes 2 of the tab's 4 columns; cmark's advance still counts the tab as 1 byte.
    func testPartiallyConsumedTabCountsOneByte() {
        XCTAssertEqual(taskItem(checked: true, text: "x [x]"), surface("+\n\t 2x [x] "))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line stays paragraph text whole, where cmark's
    /// later-line checkbox retry checks the item and drops the advanced bytes.
    func testPartiallyConsumedTabFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2x [x]\"", surface("+\n\t 2x [x] ", cmarkBugCompatible: false))
    }

    func testPartiallyConsumedTabAdvanceStopsInsideDigitRun() {
        XCTAssertEqual(taskItem(checked: true, text: "2 [x]"), surface("+\n\t 22 [x] "))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line stays paragraph text whole, where cmark's
    /// later-line checkbox retry checks the item and drops the advanced bytes.
    func testPartiallyConsumedTabBeforeDigitRunFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [x]\"", surface("+\n\t 22 [x] ", cmarkBugCompatible: false))
    }

    // MARK: Guards (equal to the reference before this fix)

    func testNULAfterWildcardDoesNotMatch() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}x [x] a\"",
            surface("+\n  2\u{0}x [x] a"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}x [x] a\"", surface("+\n  2\u{0}x [x] a", cmarkBugCompatible: false))
    }

    func testDoubleNULWildcardDoesNotMatch() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}\u{FFFD} [x] a\"",
            surface("+\n  2\u{0}\u{0} [x] a"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}\u{FFFD} [x] a\"", surface("+\n  2\u{0}\u{0} [x] a", cmarkBugCompatible: false))
    }

    /// The advance stops after the `é`'s lead byte; its orphaned continuation byte reads back as U+FFFD.
    func testMultiByteWildcardAdvanceStopsInsideScalar() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x] a"), surface("+\n  22\u{E9} [x] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the `é` stays intact, where cmark's later-line checkbox
    /// retry checks the item and orphans the `é`'s continuation byte.
    func testMultiByteWildcardFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22\u{E9} [x] a\"", surface("+\n  22\u{E9} [x] a", cmarkBugCompatible: false))
    }

    /// Flag-off (spec-correct): no checkbox, and the NUL is an ordinary U+FFFD in the paragraph text.
    func testFlagOffNoCheckbox() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\"",
            Document(parsing: "+\n  2\u{0} [x] a").debugDescription(options: []))
    }
}
