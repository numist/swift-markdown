/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A list item that begins with an empty line, and whose paragraph begins on a later line with a digit-led
/// word, has no checkbox: the paragraph does not begin with a task list item marker (Task list items
/// (extension)). Each NUL is replaced by U+FFFD (Insecure characters).
class TaskListEmptyFirstLineDigitPrefixTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    func testDigitNULPrefixThenCheckbox() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x]\"", surface("+\n  2\u{0} [x] "))
    }

    func testDigitNULPrefixThenUppercaseCheckboxAndContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [X] a\"", surface("+\n  2\u{0} [X] a"))
    }

    func testTwoDigitNULPrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22\u{FFFD} [x] a\"", surface("+\n  22\u{0} [x] a"))
    }

    func testDigitNULPrefixAfterTab() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\"", surface("+\n\t2\u{0} [x] a"))
    }

    func testLaterNULIsReplaced() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\u{FFFD}b\"", surface("+\n  2\u{0} [x] a\u{0}b"))
    }

    func testContinuationAfterDigitLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{FFFD} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"", surface("+\n  2\u{0} [x] a\n  b"))
    }

    func testNULLineOpensTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body\n            └─ Row\n               ├─ Cell\n               │  └─ Text \"c\"\n               └─ Cell\n                  └─ Text \"d\"", surface("+\n  2\u{0} [x] a|b\n  -|-\n  c|d"))
    }

    func testMultiByteLineOpensTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"22\u{E9} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  22\u{E9} [x] a|b\n  -|-"))
    }

    func testFourByteLineOpensTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{1F600} [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  2\u{1F600} [x] a|b\n  -|-"))
    }

    func testTwoDigitLineOpensTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"22 [x] a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  22 [x] a|b\n  -|-"))
    }

    func testDigitLedParagraphOpensTableOnLaterLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ Paragraph\n      │  └─ Text \"2\u{FFFD} [x] a\"\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"b\"\n         │  └─ Cell\n         │     └─ Text \"c\"\n         └─ Body", surface("+\n  2\u{0} [x] a\n  b|c\n  -|-"))
    }

    func testNULHeaderWithoutCheckboxOpensTable() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Table alignments: |-|-|\n         ├─ Head\n         │  ├─ Cell\n         │  │  └─ Text \"2\u{FFFD} a\"\n         │  └─ Cell\n         │     └─ Text \"b\"\n         └─ Body", surface("+\n  2\u{0} a|b\n  -|-"))
    }

    func testDigitLetterPrefixAfterTab() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2x [x]\"", surface("+\n\t 2x [x] "))
    }

    func testTwoDigitPrefixAfterTab() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [x]\"", surface("+\n\t 22 [x] "))
    }

    func testDigitNULLetterPrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}x [x] a\"", surface("+\n  2\u{0}x [x] a"))
    }

    func testDigitTwoNULPrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD}\u{FFFD} [x] a\"", surface("+\n  2\u{0}\u{0} [x] a"))
    }

    func testTwoDigitMultiBytePrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22\u{E9} [x] a\"", surface("+\n  22\u{E9} [x] a"))
    }

    func testDigitNULPrefixWithDefaultOptions() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{FFFD} [x] a\"",
            Document(parsing: "+\n  2\u{0} [x] a").debugDescription(options: []))
    }
}
