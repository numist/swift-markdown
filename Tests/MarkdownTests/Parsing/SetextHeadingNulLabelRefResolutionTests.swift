/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A NUL in a link label is replaced by U+FFFD (Insecure characters), so a link reference definition and a
/// shortcut reference whose labels contain NULs match, including when the reference is a setext heading's
/// content.
class SetextHeadingNulLabelRefResolutionTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let options = ParseOptions(rawValue: 0)
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// `[` `a` NUL `]` `:` `l` LF `[` `a` NUL `]` LF `-`
    func testNulLabelRefResolvesInSetextHeading() {
        let bytes: [UInt8] = [0x5b, 0x61, 0x00, 0x5d, 0x3a, 0x6c, 0x0a, 0x5b, 0x61, 0x00, 0x5d, 0x0a, 0x2d]
        let expected = "Document\n└─ Heading level: 2\n   └─ Link destination: \"l\"\n      └─ Text \"a\u{FFFD}\""
        XCTAssertEqual(expected, surface(bytes))
    }

    /// The definition's invalid UTF-8 byte and the reference's NUL both become U+FFFD, so the labels match.
    /// `[` `bar'` U+0001 0xFF NUL NUL `]` `:` `l` LF `[` `bar'` U+0001 NUL NUL NUL `]` LF `-`
    func testInvalidByteAndNulLabelsMatchInSetextHeading() {
        let bytes: [UInt8] = [
            0x5b, 0x62, 0x61, 0x72, 0x27, 0x01, 0xff, 0x00, 0x00, 0x5d, 0x3a, 0x6c, 0x0a,
            0x5b, 0x62, 0x61, 0x72, 0x27, 0x01, 0x00, 0x00, 0x00, 0x5d, 0x0a, 0x2d,
        ]
        let expected = "Document\n└─ Heading level: 2\n   └─ Link destination: \"l\"\n      └─ Text \"bar\u{2019}\u{0001}\u{FFFD}\u{FFFD}\u{FFFD}\""
        XCTAssertEqual(expected, surface(bytes))
    }
}
