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
/// Each NUL is replaced by U+FFFD (Insecure characters). Each input ends in its
/// `ParseOptions` raw value byte.
class TaskListBlockQuoteFirstBlockNULTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let (markdown, options) = DocumentRegressionTests.splitInput(bytes)!
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testNULBeforeUnclosedProcessingInstruction() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4]))
    }

    func testTrailingNULAfterLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] \u{fffd}\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 0, 4]))
    }

    func testNULBeforeUnclosedDeclaration() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<!X\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4]))
    }

    func testLinkTitleSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface([45, 32, 62, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 4]))
    }

    func testNULLaterOnLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] b\u{fffd}c\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 0, 99, 10, 4]))
    }

    func testUnclosedProcessingInstructionBeforeMultiByteLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 50, 195, 169, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testNULBeforeUnclosedCDATA() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<![CDATA[\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 91, 67, 68, 65, 84, 65, 91, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testNULBeforeUnclosedDeclarationAfterTwoDigits() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<!X\"\n            ├─ SoftBreak\n            └─ Text \"22\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testReferenceDefinitionTitleSpanningLines() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ BlockQuote\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface([45, 32, 62, 91, 97, 93, 58, 32, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 10, 10, 91, 97, 93, 10, 4]))
    }

    func testNULBeforeLinkTitleSpanningLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\u{fffd}\"\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface([45, 32, 62, 120, 0, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 10, 4]))
    }

    func testSetextHeadingOverLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Heading level: 1\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 61, 61, 61, 10, 4]))
    }

    func testTablePrecedingLinesStayParagraph() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  ├─ Text \"a\u{fffd}<?\"\n         │  ├─ SoftBreak\n         │  └─ Text \"2\u{fffd} [x]\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"b\"\n            │  └─ Cell\n            │     └─ Text \"c\"\n            └─ Body", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 98, 124, 99, 10, 32, 32, 62, 45, 124, 45, 10, 4]))
    }

    func testNULInsideUnclosedProcessingInstruction() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?b\u{fffd}c\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 60, 63, 98, 0, 99, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testNestedQuoteLazyLines() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ BlockQuote\n            └─ Paragraph\n               ├─ Text \"\u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               ├─ Text \"2\u{fffd} [x] b\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [a]:\"\n               ├─ SoftBreak\n               ├─ Text \"/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               ├─ Text \"2\u{fffd} [x] b\u{fffd}/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{fffd}\t<?p;;\u{fffd} \u{0C}\u{fffd}\u{fffd}\u{fffd};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}ha\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}qqqqqqqqqqqqqqq\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd} \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{04}\u{fffd}qq\u{fffd}\u{fffd}\u{fffd};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}ha\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{01}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{05}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04}\t\u{fffd}t \t\u{fffd}\u{fffd}\t\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"\u{04}\u{fffd}\u{fffd}\u{fffd};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}qqqqqqq\u{fffd}\u{fffd}\u{fffd}\u{fffd}\"\n               ├─ InlineHTML <qq  >\n               ├─ Text \" \u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               ├─ Text \"2\u{fffd} [\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}x] b\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{fffd} [a]:\"\n               ├─ SoftBreak\n               ├─ Text \"/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               └─ Text \"2\u{fffd} [x] b\u{fffd}\"", surface([45, 32, 62, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 10, 0, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 47, 117, 10, 32, 9, 174, 250, 9, 60, 63, 112, 59, 59, 255, 32, 12, 128, 0, 0, 59, 10, 63, 255, 255, 255, 104, 97, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 4, 59, 10, 63, 255, 32, 255, 255, 255, 133, 255, 4, 255, 113, 113, 128, 0, 0, 59, 10, 63, 255, 253, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 9, 174, 116, 32, 9, 174, 250, 9, 3, 192, 103, 115, 10, 4, 0, 0, 0, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 113, 113, 113, 113, 113, 113, 113, 0, 0, 0, 0, 60, 113, 113, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 120, 93, 32, 98, 10, 0, 219, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 0]))
    }
}
