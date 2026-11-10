/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Each NUL in a link label is replaced by U+FFFD (Insecure characters) and counts as one character toward the
/// label's limit of 999 characters (Links). With 999 NULs the label is valid, the link reference definition forms,
/// and `=` is a paragraph rather than a setext heading underline; with 1000 the line is paragraph text, which `=`
/// underlines.
class LinkLabelNulLengthCapTests: XCTestCase {
    private func tree(nulCount: Int) -> String {
        Document(parsing: "[" + String(repeating: "\u{0}", count: nulCount) + "]:/l\n=").debugDescription(options: [])
    }

    func testLabelOf999NulsIsValid() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"=\"", tree(nulCount: 999))
    }

    func testLabelOf1000NulsIsParagraphText() {
        XCTAssertEqual(
            "Document\n└─ Heading level: 1\n   └─ Text \"[" + String(repeating: "\u{FFFD}", count: 1000) + "]:/l\"",
            tree(nulCount: 1000))
    }
}
