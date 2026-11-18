/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

class TaskListDigitPrefixUppercaseCheckboxTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    func testDigitDashPrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [X] a\"", tree("+\n  2- [X] a"))
    }

    func testMultiDigitDashPrefix() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"12- [X]\"", tree("+\n  12- [X]\t"))
    }

    func testMultiByteScalarAfterDigit() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2\u{E9} [x]\"", tree("+\n  2\u{E9} [x] "))
    }

    func testDigitDashPrefixBeforeTab() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [X]\"",
            tree("+\n  2- [X]\t"))
    }
}
