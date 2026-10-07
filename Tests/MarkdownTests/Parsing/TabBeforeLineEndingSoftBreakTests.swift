/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A tab before a line ending makes a soft line break: a hard line break needs two or more spaces or a
/// backslash before the line ending (Hard line breaks).
class TabBeforeLineEndingSoftBreakTests: XCTestCase {
    // "[" 0xC0 CR " ]:" 0xFF LF "=" LF "*" TAB CR "*"
    private static let bytes: [UInt8] = [
        0x5b, 0xc0, 0x0d, 0x20, 0x5d, 0x3a, 0xff, 0x0a, 0x3d, 0x0a, 0x2a, 0x09, 0x0d, 0x2a,
    ]
    private static let options = ParseOptions(rawValue: UInt(0x09 & 0b11011111))

    private func surface() -> String {
        Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: Self.options)
            .debugDescription(options: [])
    }

    func testTrailingTabIsSoftBreak() {
        let expected = "Document\n└─ Paragraph\n   ├─ Text \"=\"\n   ├─ SoftBreak\n   ├─ Text \"*\"\n   ├─ SoftBreak\n   └─ Text \"*\""
        XCTAssertEqual(expected, surface())
    }
}
