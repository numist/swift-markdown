/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// The later-line tasklist retry fires on a lazy paragraph continuation whose deepest matched container is
/// the item.
///
/// Ground truth is cmark-gfm (flag-ON). When a block quote inside the item fails its `>` check, the item is
/// the line's deepest matched container, so cmark's `open_tasklist_item` retry (see
/// `TaskListRetryItemWithChildTests`) runs on it: the ITEM gets the checkbox, and the rest of the line past
/// the 3-byte advance continues the block quote's paragraph lazily. Position-free compare surface.
class TaskListRetryLazyContinuationTests: XCTestCase {
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var options = ParseOptions(rawValue: UInt(0x0a & 0b11011111))
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testLazyBlockQuoteParagraph() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"[x] a\"", surface("- > a\n  2- [x] a"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line continues the quote's paragraph whole, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testLazyBlockQuoteParagraphFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2- [x] a\"", surface("- > a\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testLazyListItemParagraphInBlockQuote() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ UnorderedList\n            └─ ListItem\n               └─ Paragraph\n                  ├─ Text \"a\"\n                  ├─ SoftBreak\n                  └─ Text \"[x] a\"", surface("- > - a\n  2- [x] a"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line continues the quoted item's paragraph whole,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testLazyListItemParagraphInBlockQuoteFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ UnorderedList\n            └─ ListItem\n               └─ Paragraph\n                  ├─ Text \"a\"\n                  ├─ SoftBreak\n                  └─ Text \"2- [x] a\"", surface("- > - a\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testBlankLineEndsLazyContinuation() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      ├─ BlockQuote\n      │  └─ Paragraph\n      │     └─ Text \"a\"\n      └─ Paragraph\n         └─ Text \"[x] a\"", surface("- > a\n\n  2- [x] a"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the line after the blank line is the item's second
    /// paragraph, whole, where cmark's later-line checkbox retry checks the item and drops the advanced
    /// bytes.
    func testBlankLineEndsLazyContinuationFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ BlockQuote\n      │  └─ Paragraph\n      │     └─ Text \"a\"\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- > a\n\n  2- [x] a", cmarkBugCompatible: false))
    }

    func testTabIndentedLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"[x] b\"", surface("- > a\n\t2- [x] b"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line continues the quote's paragraph whole, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testTabIndentedLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2- [x] b\"", surface("- > a\n\t2- [x] b", cmarkBugCompatible: false))
    }

    func testResidualWhitespaceAfterAdvanceStaysInCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            └─ InlineCode `a  [x] b`", surface("- > `a\n  22  [x] b`"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the code span holds the whole lazy line after its stripped
    /// indent, where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testLazyLineInCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            └─ InlineCode `a 22  [x] b`", surface("- > `a\n  22  [x] b`", cmarkBugCompatible: false))
    }

    func testAdvanceInsideNulReplacement() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"\u{FFFD} [x] b\"", surface("- > a\n  2\0 [x] b"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line, its NUL an ordinary U+FFFD, continues the
    /// quote's paragraph whole, where cmark's later-line checkbox retry checks the item and drops the
    /// advanced bytes.
    func testNULLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2\u{FFFD} [x] b\"", surface("- > a\n  2\0 [x] b", cmarkBugCompatible: false))
    }

    func testAdvanceInsideNulReplacementAfterMatchedContinuation() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"b\"\n            ├─ SoftBreak\n            └─ Text \"\u{FFFD} [x] c\"", surface("- > a\n  > b\n  2\0 [x] c"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line, its NUL an ordinary U+FFFD, continues the
    /// quote's paragraph whole, where cmark's later-line checkbox retry checks the item and drops the
    /// advanced bytes.
    func testNULLazyLineAfterMatchedContinuationFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"b\"\n            ├─ SoftBreak\n            └─ Text \"2\u{FFFD} [x] c\"", surface("- > a\n  > b\n  2\0 [x] c", cmarkBugCompatible: false))
    }

    func testIndentedLazyLineIsNotCode() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"22 [x] b\"", surface("- > a\n      22 [x] b"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line continues the quote's paragraph whole, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testIndentedLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"22 [x] b\"", surface("- > a\n      22 [x] b", cmarkBugCompatible: false))
    }

    func testScanFailureLeavesItemUnchecked() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2 [x] b\"", surface("- > a\n  2 [x] b"))
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2 [x] b\"", surface("- > a\n  2 [x] b", cmarkBugCompatible: false))
    }

    func testAdvanceInsideMultiByteWildcard() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"\u{FFFD} [x] b\"", surface("- > a\n  22\u{E9} [x] b"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line continues the quote's paragraph whole, where
    /// cmark's later-line checkbox retry checks the item and orphans the `é`'s continuation byte.
    func testMultiByteLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x] b\"", surface("- > a\n  22\u{E9} [x] b", cmarkBugCompatible: false))
    }

    func testOrphanedNulBytesNeverOpenTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{FFFD} [x] |b\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface("- > a\n  2\0 [x] |b\n  > -|-"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line is an ordinary header row for the quote's
    /// delimiter row, where cmark's later-line checkbox retry checks the item, leaving orphaned bytes that
    /// stop its header scan.
    func testNULLazyLineHeadsTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  └─ Text \"a\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"2\u{FFFD} [x]\"\n            │  └─ Cell\n            │     └─ Text \"b\"\n            └─ Body", surface("- > a\n  2\0 [x] |b\n  > -|-", cmarkBugCompatible: false))
    }

    func testOrphanedWildcardBytesNeverOpenTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{FFFD} [x] |b\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface("- > a\n  22\u{E9} [x] |b\n  > -|-"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line is an ordinary header row for the quote's
    /// delimiter row, where cmark's later-line checkbox retry checks the item, leaving an orphaned byte
    /// that stops its header scan.
    func testMultiByteLazyLineHeadsTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  └─ Text \"a\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"22\u{E9} [x]\"\n            │  └─ Cell\n            │     └─ Text \"b\"\n            └─ Body", surface("- > a\n  22\u{E9} [x] |b\n  > -|-", cmarkBugCompatible: false))
    }

    func testOrphanedBytesOnEarlierLineNeverOpenTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{FFFD} [x] b\"\n            ├─ SoftBreak\n            ├─ Text \"c|d\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface("- > a\n  2\0 [x] b\n  > c|d\n  > -|-"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the quote's last line heads a table under its paragraph,
    /// where cmark's later-line checkbox retry checks the item, leaving orphaned bytes that stop its header
    /// scan.
    func testNULLazyLineThenTableFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  ├─ Text \"a\"\n         │  ├─ SoftBreak\n         │  └─ Text \"2\u{FFFD} [x] b\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"c\"\n            │  └─ Cell\n            │     └─ Text \"d\"\n            └─ Body", surface("- > a\n  2\0 [x] b\n  > c|d\n  > -|-", cmarkBugCompatible: false))
    }
}
