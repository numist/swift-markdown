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
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.cmarkBugCompatibility]).debugDescription(options: [])
    }

    private func taskItem(checked: Bool, text: String) -> String {
        "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [\(checked ? "x" : " ")]\n      └─ Paragraph\n         └─ Text \"\(text)\""
    }

    // MARK: NUL wildcard: the advance stops inside its U+FFFD

    func testNULWildcardThenCheckbox() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x]"), surface("+\n  2\u{0} [x] "))
    }

    func testNULWildcardThenUppercaseCheckboxAndContent() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [X] a"), surface("+\n  2\u{0} [X] a"))
    }

    func testNULWildcardThenCheckboxAndContent() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x] a"), surface("+\n  2\u{0} [x] a"))
    }

    /// Two digits put the NUL at the advance's last byte, orphaning two of its three bytes.
    func testNULWildcardAfterTwoDigitsOrphansTwoBytes() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD}\u{FFFD} [x] a"), surface("+\n  22\u{0} [x] a"))
    }

    /// A partly consumed tab counts one byte, so the NUL is the advance's last byte.
    func testNULWildcardAfterPartiallyConsumedTabOrphansTwoBytes() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD}\u{FFFD} [x] a"), surface("+\n\t2\u{0} [x] a"))
    }

    func testLaterNULOnOrphanLineIsReplaced() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x] a\u{FFFD}b"), surface("+\n  2\u{0} [x] a\u{0}b"))
    }

    func testContinuationAfterOrphanLine() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{FFFD} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"",
            surface("+\n  2\u{0} [x] a\n  b"))
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

    func testMultiByteOrphanLineDoesNotOpenTable() {
        XCTAssertEqual(paragraphItem(["\u{FFFD} [x] a|b", "-|-"]), surface("+\n  22\u{E9} [x] a|b\n  -|-"))
    }

    func testFourByteOrphanLineDoesNotOpenTable() {
        XCTAssertEqual(paragraphItem(["\u{FFFD}\u{FFFD} [x] a|b", "-|-"]), surface("+\n  2\u{1F600} [x] a|b\n  -|-"))
    }

    /// Control: an advance that ends on a scalar boundary leaves nothing orphaned, so the table opens.
    func testOrphanFreeLineOpensTable() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"[x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body",
            surface("+\n  22 [x] a|b\n  -|-"))
    }

    func testOrphanLedParagraphDoesNotOpenTableOnLaterLine() {
        XCTAssertEqual(paragraphItem(["\u{FFFD} [x] a", "b|c", "-|-"]), surface("+\n  2\u{0} [x] a\n  b|c\n  -|-"))
    }

    /// Without a checkbox the scan doesn't match, nothing is advanced, and the NUL is an ordinary U+FFFD.
    func testNULHeaderWithoutCheckboxOpensTable() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body",
            surface("+\n  2\u{0} a|b\n  -|-"))
    }

    // MARK: Tabs count one byte

    /// The item's indent consumes 2 of the tab's 4 columns; cmark's advance still counts the tab as 1 byte.
    func testPartiallyConsumedTabCountsOneByte() {
        XCTAssertEqual(taskItem(checked: true, text: "x [x]"), surface("+\n\t 2x [x] "))
    }

    func testPartiallyConsumedTabAdvanceStopsInsideDigitRun() {
        XCTAssertEqual(taskItem(checked: true, text: "2 [x]"), surface("+\n\t 22 [x] "))
    }

    // MARK: Guards (equal to the reference before this fix)

    func testNULAfterWildcardDoesNotMatch() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}x [x] a\"",
            surface("+\n  2\u{0}x [x] a"))
    }

    func testDoubleNULWildcardDoesNotMatch() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}\u{FFFD} [x] a\"",
            surface("+\n  2\u{0}\u{0} [x] a"))
    }

    /// The advance stops after the `é`'s lead byte; its orphaned continuation byte reads back as U+FFFD.
    func testMultiByteWildcardAdvanceStopsInsideScalar() {
        XCTAssertEqual(taskItem(checked: true, text: "\u{FFFD} [x] a"), surface("+\n  22\u{E9} [x] a"))
    }

    /// Flag-off (spec-correct): no checkbox, and the NUL is an ordinary U+FFFD in the paragraph text.
    func testFlagOffNoCheckbox() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\"",
            Document(parsing: "+\n  2\u{0} [x] a").debugDescription(options: []))
    }
}
