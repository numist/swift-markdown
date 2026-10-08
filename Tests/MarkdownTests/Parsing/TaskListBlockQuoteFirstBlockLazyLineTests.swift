/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A list item whose first block is a block quote is not a task list item (Task list items (extension)), so
/// `[x]` on a later line of the item is not a checkbox.
class TaskListBlockQuoteFirstBlockLazyLineTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        let options = ParseOptions(rawValue: UInt(0x0a & 0b11011111))
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testLazyBlockQuoteParagraph() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2- [x] a\"", surface("- > a\n  2- [x] a"))
    }

    func testLazyListItemParagraphInBlockQuote() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ UnorderedList\n            └─ ListItem\n               └─ Paragraph\n                  ├─ Text \"a\"\n                  ├─ SoftBreak\n                  └─ Text \"2- [x] a\"", surface("- > - a\n  2- [x] a"))
    }

    func testBlankLineEndsLazyContinuation() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ BlockQuote\n      │  └─ Paragraph\n      │     └─ Text \"a\"\n      └─ Paragraph\n         └─ Text \"2- [x] a\"", surface("- > a\n\n  2- [x] a"))
    }

    func testTabIndentedLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2- [x] b\"", surface("- > a\n\t2- [x] b"))
    }

    func testLazyLineInCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            └─ InlineCode `a 22  [x] b`", surface("- > `a\n  22  [x] b`"))
    }

    func testNULLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2\u{FFFD} [x] b\"", surface("- > a\n  2\0 [x] b"))
    }

    func testNULLazyLineAfterMatchedContinuation() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"b\"\n            ├─ SoftBreak\n            └─ Text \"2\u{FFFD} [x] c\"", surface("- > a\n  > b\n  2\0 [x] c"))
    }

    func testIndentedLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"22 [x] b\"", surface("- > a\n      22 [x] b"))
    }

    func testDigitPrefixedLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2 [x] b\"", surface("- > a\n  2 [x] b"))
    }

    func testMultiByteLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x] b\"", surface("- > a\n  22\u{E9} [x] b"))
    }

    func testNULLazyLineHeadsTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  └─ Text \"a\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"2\u{FFFD} [x]\"\n            │  └─ Cell\n            │     └─ Text \"b\"\n            └─ Body", surface("- > a\n  2\0 [x] |b\n  > -|-"))
    }

    func testMultiByteLazyLineHeadsTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  └─ Text \"a\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"22\u{E9} [x]\"\n            │  └─ Cell\n            │     └─ Text \"b\"\n            └─ Body", surface("- > a\n  22\u{E9} [x] |b\n  > -|-"))
    }

    func testNULLazyLineThenTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  ├─ Text \"a\"\n         │  ├─ SoftBreak\n         │  └─ Text \"2\u{FFFD} [x] b\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"c\"\n            │  └─ Cell\n            │     └─ Text \"d\"\n            └─ Body", surface("- > a\n  2\0 [x] b\n  > c|d\n  > -|-"))
    }
}
