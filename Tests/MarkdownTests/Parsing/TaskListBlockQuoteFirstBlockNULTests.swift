/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// In a list item whose first block is a block quote, a line of `2`, a NUL and ` [x]` is not an ordered list item: a
/// NUL is replaced by U+FFFD (Insecure characters), and an ordered list marker ends in `.` or `)` (List items). The
/// line is a lazy continuation line of the block quote's paragraph (Block quotes), so `[x]` is text.
class TaskListBlockQuoteFirstBlockNULTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    func testNULBeforeUnclosedProcessingInstruction() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a\0<?\n  2\0 [x] "))
    }

    func testTrailingNULAfterLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] \u{fffd}\"", surface("- >a<?\n  2\0 [x] \0"))
    }

    func testNULBeforeUnclosedDeclaration() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<!X\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a\0<!X\n  2\0 [x] "))
    }

    func testLinkTitleSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface("- >[a](/u \"\n  2\0 [x] \")"))
    }

    func testNULLaterOnLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] b\u{fffd}c\"", surface("- >a<?\n  2\0 [x] b\0c\n"))
    }

    func testUnclosedProcessingInstructionBeforeMultiByteLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x]\"", surface("- >a\0<?\n  22\u{E9} [x] \n"))
    }

    func testNULBeforeUnclosedCDATA() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<![CDATA[\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a\0<![CDATA[\n  2\0 [x] \n"))
    }

    func testNULBeforeUnclosedDeclarationAfterTwoDigits() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<!X\"\n            ├─ SoftBreak\n            └─ Text \"22\u{fffd} [x]\"", surface("- >a\0<!X\n  22\0 [x] \n"))
    }

    func testReferenceDefinitionTitleSpanningLines() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ BlockQuote\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("- >[a]: /u \"\n  2\0 [x] \"\n\n[a]\n"))
    }

    func testNULBeforeLinkTitleSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\u{fffd}\"\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface("- >x\0[a](/u \"\n  2\0 [x] \")\n"))
    }

    func testSetextHeadingOverLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Heading level: 1\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a\0<?\n  2\0 [x] \n  >===\n"))
    }

    func testTablePrecedingLinesStayParagraph() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  ├─ Text \"a\u{fffd}<?\"\n         │  ├─ SoftBreak\n         │  └─ Text \"2\u{fffd} [x]\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"b\"\n            │  └─ Cell\n            │     └─ Text \"c\"\n            └─ Body", surface("- >a\0<?\n  2\0 [x] \n  >b|c\n  >-|-\n"))
    }

    func testNULInsideUnclosedProcessingInstruction() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?b\u{fffd}c\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<?b\0c\n  2\0 [x] \n"))
    }
}
