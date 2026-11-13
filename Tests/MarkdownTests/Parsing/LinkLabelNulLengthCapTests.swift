/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Each NUL in a link label is replaced by U+FFFD (Insecure characters) and counts as its three bytes toward the
/// label's limit of 1000 bytes. With 333 NULs (999 bytes) the label is valid, the link reference definition forms,
/// and `=` is a paragraph rather than a setext heading underline; with 334 (1002 bytes) the line is paragraph text,
/// which `=` underlines.
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
