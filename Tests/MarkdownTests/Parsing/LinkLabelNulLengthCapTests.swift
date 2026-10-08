/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Each NUL in a link label is replaced by U+FFFD (Insecure characters) and counts as one character toward
/// the label's limit of 999 characters (Links), so these labels are valid, the link reference definition
/// forms, and `=` is a paragraph rather than a setext heading underline.
class LinkLabelNulLengthCapTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let options = ParseOptions(rawValue: 0)
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// `[` + NUL×count + `]:/l` LF `=`
    private func input(nulCount: Int) -> [UInt8] {
        [0x5b] + Array(repeating: 0x00, count: nulCount) + [0x5d, 0x3a, 0x2f, 0x6c, 0x0a, 0x3d]
    }

    func testLabelOf334NulsIsValid() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"=\"",
            surface(input(nulCount: 334)))
    }

    func testLabelOf333NulsIsValid() {
        let expected = "Document\n└─ Paragraph\n   └─ Text \"=\""
        XCTAssertEqual(expected, surface(input(nulCount: 333)))
    }
}
