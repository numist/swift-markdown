/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class TaskListDigitPrefixUppercaseCheckboxTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    /// Flag-off (spec-correct): a paragraph beginning `2-` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line stays paragraph text whole, where cmark's
    /// later-line checkbox retry checks the item.
    func testUppercaseCheckboxThenContentFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [X] a\"", surface("+\n  2- [X] a"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `12-` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line stays paragraph text whole, where cmark's
    /// later-line checkbox retry checks the item.
    func testMultiDigitUppercaseCheckboxFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"12- [X]\"", surface("+\n  12- [X]\t"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2é` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and the line stays paragraph text whole, where cmark's
    /// later-line checkbox retry checks the item.
    func testMultiByteScalarAfterDigitFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{E9} [x]\"", surface("+\n  2\u{E9} [x] "))
    }

    /// Flag-off (spec-correct): no checkbox; the whole continuation line stays paragraph text.
    func testFlagOffNoCheckbox() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [X]\"",
            Document(parsing: "+\n  2- [X]\t").debugDescription(options: []))
    }
}
