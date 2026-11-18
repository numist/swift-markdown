/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// Each NUL counts as the three bytes of the U+FFFD that replaces it toward a link label's 1000-byte limit, and a
// definition leaves no paragraph text for `=` to underline (Link reference definitions).
class LinkLabelNulLengthCapTests: XCTestCase {
    private func tree(nulCount: Int) -> String {
        Document(parsing: "[" + String(repeating: "\u{0}", count: nulCount) + "]:/l\n=").debugDescription(options: [])
    }

    func testLabelOf333NulsIsValid() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"=\"", tree(nulCount: 333))
    }

    func testLabelOf334NulsIsParagraphText() {
        XCTAssertEqual(
            "Document\n└─ Heading level: 1\n   └─ Text \"[" + String(repeating: "\u{FFFD}", count: 334) + "]:/l\"",
            tree(nulCount: 334))
    }
}
