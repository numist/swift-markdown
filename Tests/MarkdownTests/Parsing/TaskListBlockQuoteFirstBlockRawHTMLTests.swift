/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A lazy continuation line of a block quote in a list item holds a NUL, which is replaced by U+FFFD (Insecure
/// characters), or a multibyte character, and a `[x]` that does not begin a paragraph and so is text (Task list items
/// (extension)). Raw HTML opened on an earlier line may close on that line (Raw HTML).
class TaskListBlockQuoteFirstBlockRawHTMLTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.disableSmartOpts]).debugDescription(options: [])
    }

    func testUnclosedProcessingInstruction() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", tree("- >a<?\n  2\u{0} [x] \n"))
    }

    func testProcessingInstructionSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <?\n2\u{fffd} [x] ?>", tree("- >a<?\n  2\u{0} [x] ?>\n"))
    }

    func testUnclosedProcessingInstructionAfterTwoDigits() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{fffd} [x]\"", tree("- >a<?\n  22\u{0} [x] \n"))
    }

    func testUnclosedProcessingInstructionBeforeMultiByteScalar() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x]\"", tree("- >a<?\n  22\u{E9} [x] \n"))
    }

    func testUnclosedCDATA() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<![CDATA[\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", tree("- >a<![CDATA[\n  2\u{0} [x] \n"))
    }

    func testUnclosedDeclaration() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<!X\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", tree("- >a<!X\n  2\u{0} [x] \n"))
    }

    func testCommentSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <!--\n2\u{fffd} [x] -->", tree("- >a<!--\n  2\u{0} [x] -->\n"))
    }

    func testQuotedAttributeValueSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <a b=\"\n2\u{fffd} [x] \">", tree("- >a<a b=\"\n  2\u{0} [x] \">\n"))
    }

    func testShortcutReferenceOnLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"22\u{E9} \"\n            └─ Link destination: \"/u\"\n               └─ Text \"x\"", tree("- >a\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    func testLinkTitleSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", tree("- >x[a](/u \"\n  2\u{0} [x] \")\n"))
    }

    func testUnclosedProcessingInstructionBeforeDigitAndMultiByteScalar() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{E9} [x]\"", tree("- >a<?\n  2\u{E9} [x] \n"))
    }
}
