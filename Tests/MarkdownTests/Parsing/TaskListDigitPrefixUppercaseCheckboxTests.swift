/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A list item whose paragraph begins with a digit-led word before `[x]` or `[X]` has no checkbox: the
/// paragraph does not begin with a task list item marker (Task list items (extension)).
class TaskListDigitPrefixUppercaseCheckboxTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    func testDigitDashPrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [X] a\"", surface("+\n  2- [X] a"))
    }

    func testMultiDigitDashPrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"12- [X]\"", surface("+\n  12- [X]\t"))
    }

    func testMultiByteScalarAfterDigit() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{E9} [x]\"", surface("+\n  2\u{E9} [x] "))
    }

    func testDigitDashPrefixWithDefaultOptions() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [X]\"",
            Document(parsing: "+\n  2- [X]\t").debugDescription(options: []))
    }
}
