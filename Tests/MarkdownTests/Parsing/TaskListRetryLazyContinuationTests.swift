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
    private func surface(_ markdown: String) -> String {
        var options = ParseOptions(rawValue: UInt(0x0a & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testLazyBlockQuoteParagraph() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"[x] a\"", surface("- > a\n  2- [x] a"))
    }

    func testLazyListItemParagraphInBlockQuote() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ UnorderedList\n            └─ ListItem\n               └─ Paragraph\n                  ├─ Text \"a\"\n                  ├─ SoftBreak\n                  └─ Text \"[x] a\"", surface("- > - a\n  2- [x] a"))
    }

    func testBlankLineEndsLazyContinuation() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      ├─ BlockQuote\n      │  └─ Paragraph\n      │     └─ Text \"a\"\n      └─ Paragraph\n         └─ Text \"[x] a\"", surface("- > a\n\n  2- [x] a"))
    }

    func testTabIndentedLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"[x] b\"", surface("- > a\n\t2- [x] b"))
    }

    func testResidualWhitespaceAfterAdvanceStaysInCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            └─ InlineCode `a  [x] b`", surface("- > `a\n  22  [x] b`"))
    }

    func testAdvanceInsideNulReplacement() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"\u{FFFD} [x] b\"", surface("- > a\n  2\0 [x] b"))
    }

    func testAdvanceInsideNulReplacementAfterMatchedContinuation() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"b\"\n            ├─ SoftBreak\n            └─ Text \"\u{FFFD} [x] c\"", surface("- > a\n  > b\n  2\0 [x] c"))
    }

    func testIndentedLazyLineIsNotCode() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"22 [x] b\"", surface("- > a\n      22 [x] b"))
    }

    func testScanFailureLeavesItemUnchecked() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2 [x] b\"", surface("- > a\n  2 [x] b"))
    }

    func testAdvanceInsideMultiByteWildcard() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"\u{FFFD} [x] b\"", surface("- > a\n  22\u{E9} [x] b"))
    }

    func testOrphanedNulBytesNeverOpenTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{FFFD} [x] |b\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface("- > a\n  2\0 [x] |b\n  > -|-"))
    }

    func testOrphanedWildcardBytesNeverOpenTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{FFFD} [x] |b\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface("- > a\n  22\u{E9} [x] |b\n  > -|-"))
    }

    func testOrphanedBytesOnEarlierLineNeverOpenTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{FFFD} [x] b\"\n            ├─ SoftBreak\n            ├─ Text \"c|d\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface("- > a\n  2\0 [x] b\n  > c|d\n  > -|-"))
    }
}
