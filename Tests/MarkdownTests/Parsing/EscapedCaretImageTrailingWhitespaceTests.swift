/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// An escaped-caret image `![\^…]` ending a paragraph or setext heading whose last line has trailing whitespace.
///
/// Ground truth is cmark-gfm (flag-ON). cmark's escaped-caret image label capture over-reads one byte past the
/// `]`. A line-built block's buffer keeps each line's trailing whitespace (only the line ending is replaced by a
/// `\n`), and the inline subject's rtrim shortens its length without touching those bytes, so the over-read
/// lands on the first trailing whitespace byte instead of the `\n`. Position-free compare surface.
class EscapedCaretImageTrailingWhitespaceTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        var options = ParseOptions(rawValue: UInt(0xe4 & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private static func paragraph(_ text: String) -> String {
        "Document\n└─ Paragraph\n   └─ Text \"\(text)\""
    }

    func testTrailingSpace() {
        XCTAssertEqual(Self.paragraph("[^a] ]"), surface("![\\^a] "))
    }

    func testTrailingTab() {
        XCTAssertEqual(Self.paragraph("[^a]\u{9}]"), surface("![\\^a]\u{9}"))
    }

    func testOnlyFirstOfTwoTrailingSpaces() {
        XCTAssertEqual(Self.paragraph("[^a] ]"), surface("![\\^a]  "))
    }

    func testLongerLabel() {
        XCTAssertEqual(Self.paragraph("[^ab] ]"), surface("![\\^ab] "))
    }

    func testTrailingSpaceThenNewline() {
        XCTAssertEqual(Self.paragraph("[^a] ]"), surface("![\\^a] \n"))
    }

    func testTrailingSpaceThenCRLF() {
        XCTAssertEqual(Self.paragraph("[^a] ]"), surface("![\\^a] \r\n"))
    }

    func testTrailingSpaceBeforeBlankLine() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ Text \"[^a] ]\"\n└─ Paragraph\n   └─ Text \"b\"", surface("![\\^a] \n\nb"))
    }

    func testLastOfTwoLines() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Text \"[^a] ]\"", surface("x\n![\\^a] "))
    }

    func testInBlockQuote() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"[^a] ]\"", surface("> ![\\^a] "))
    }

    func testLastOfTwoBlockQuoteLines() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      └─ Text \"[^a] ]\"", surface("> x\n> ![\\^a] "))
    }

    func testLazyBlockQuoteContinuation() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      └─ Text \"[^a] ]\"", surface("> x\n![\\^a] "))
    }

    func testInListItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"[^a] ]\"", surface("- ![\\^a] "))
    }

    func testSetextHeadingTrailingSpace() {
        XCTAssertEqual("Document\n└─ Heading level: 1\n   └─ Text \"[^a] ]\"", surface("![\\^a] \n==="))
    }

    func testSetextHeadingTrailingTab() {
        XCTAssertEqual("Document\n└─ Heading level: 1\n   └─ Text \"[^a]\u{9}]\"", surface("![\\^a]\u{9}\n==="))
    }

    func testSetextHeadingLastOfTwoLines() {
        XCTAssertEqual("Document\n└─ Heading level: 1\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Text \"[^a] ]\"", surface("x\n![\\^a] \n==="))
    }

    func testFirstOfTabThenSpace() {
        XCTAssertEqual(Self.paragraph("[^a]\u{9}]"), surface("![\\^a]\u{9} "))
    }

    func testAfterStrippedReferenceDefinition() {
        XCTAssertEqual(Self.paragraph("[^a] ]"), surface("[x]: /u\n![\\^a] "))
    }

    func testTaskListItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [ ]\n      └─ Paragraph\n         └─ Text \"[^a] ]\"", surface("- [ ] ![\\^a] "))
    }

    func testNULElsewhereInBlockQuoteParagraph() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"\u{FFFD}\"\n      ├─ SoftBreak\n      └─ Text \"[^a] ]\"", surface("> \u{0}\n> ![\\^a] "))
    }

    func testLazyListItemContinuation() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"x\"\n         ├─ SoftBreak\n         └─ Text \"[^a] ]\"", surface("- x\n![\\^a] "))
    }

    func testSetextHeadingInBlockQuote() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Heading level: 1\n      └─ Text \"[^a] ]\"", surface("> ![\\^a] \n> ==="))
    }

    func testSetextHeadingInListItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         └─ Text \"[^a] ]\"", surface("- ![\\^a] \n  ==="))
    }

    // Controls: already matching cmark.

    func testCRLFWithoutTrailingWhitespace() {
        XCTAssertEqual(Self.paragraph("[^a]\n]"), surface("![\\^a]\r\n"))
    }

    func testHardBreakMidParagraph() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"[^a] ]\"\n   ├─ LineBreak\n   └─ Text \"b\"", surface("![\\^a]  \nb"))
    }

    func testTrailingSpaceNotOnLastLine() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x [^a] ]\"\n   ├─ SoftBreak\n   └─ Text \"y\"", surface("x ![\\^a] \ny"))
    }

    func testNonImageForm() {
        XCTAssertEqual(Self.paragraph("[^a]]"), surface("[\\^a] "))
    }

    func testATXHeading() {
        XCTAssertEqual("Document\n└─ Heading level: 1\n   └─ Text \"[^a]\"", surface("# ![\\^a] "))
    }
}
