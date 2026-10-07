/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A list item whose first block is a block quote is not a task list item (Task list items (extension)), so
/// `[x]` on a later line of the item is not a checkbox.
/// Raw HTML opened on an earlier line may close on that line (Raw HTML).
class TaskListBlockQuoteFirstBlockRawHTMLTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.disableSmartOpts]).debugDescription(options: [])
    }

    func testUnclosedProcessingInstruction() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<?\n  2\u{0} [x] \n"))
    }

    func testProcessingInstructionSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <?\n2\u{fffd} [x] ?>", surface("- >a<?\n  2\u{0} [x] ?>\n"))
    }

    func testUnclosedProcessingInstructionAfterTwoDigits() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{fffd} [x]\"", surface("- >a<?\n  22\u{0} [x] \n"))
    }

    func testUnclosedProcessingInstructionBeforeMultiByteScalar() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x]\"", surface("- >a<?\n  22\u{E9} [x] \n"))
    }

    func testUnclosedCDATA() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<![CDATA[\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<![CDATA[\n  2\u{0} [x] \n"))
    }

    func testUnclosedDeclaration() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<!X\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<!X\n  2\u{0} [x] \n"))
    }

    func testCommentSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <!--\n2\u{fffd} [x] -->", surface("- >a<!--\n  2\u{0} [x] -->\n"))
    }

    func testQuotedAttributeValueSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <a b=\"\n2\u{fffd} [x] \">", surface("- >a<a b=\"\n  2\u{0} [x] \">\n"))
    }

    func testShortcutReferenceOnLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"22\u{E9} \"\n            └─ Link destination: \"/u\"\n               └─ Text \"x\"", surface("- >a\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    /// A paragraph that begins with `22é` does not begin with a task list item marker, so `[x]` is a shortcut
    /// reference link.
    func testShortcutReferenceOnDigitLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"22\u{E9} \"\n         └─ Link destination: \"/u\"\n            └─ Text \"x\"", surface("+\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    func testLinkTitleSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface("- >x[a](/u \"\n  2\u{0} [x] \")\n"))
    }

    func testUnclosedProcessingInstructionBeforeDigitAndMultiByteScalar() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{E9} [x]\"", surface("- >a<?\n  2\u{E9} [x] \n"))
    }
}
