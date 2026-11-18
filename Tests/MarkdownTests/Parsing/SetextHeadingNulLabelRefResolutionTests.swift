/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

class SetextHeadingNulLabelRefResolutionTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    func testNulLabelRefResolvesInSetextHeading() {
        let expected = "Document\n└─ Heading level: 2\n   └─ Link destination: \"l\"\n      └─ Text \"a\u{FFFD}\""
        XCTAssertEqual(expected, tree("[a\0]:l\n[a\0]\n-"))
    }

    func testReplacementCharacterAndNulLabelsMatchInSetextHeading() {
        let expected = "Document\n└─ Heading level: 2\n   └─ Link destination: \"l\"\n      └─ Text \"bar\u{2019}\u{0001}\u{FFFD}\u{FFFD}\u{FFFD}\""
        XCTAssertEqual(expected, tree("[bar'\u{01}\u{FFFD}\0\0]:l\n[bar'\u{01}\0\0\0]\n-"))
    }
}
