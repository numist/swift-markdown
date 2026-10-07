/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A backslash before `&` in a link destination escapes it (Backslash escapes), so the character reference
/// that follows is literal text.
class LinkDestinationEntityEscapeOrderTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let options = ParseOptions(rawValue: 0)
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    // "[a](\&#3;)"
    private static let numericDest: [UInt8] = [0x5b, 0x61, 0x5d, 0x28, 0x5c, 0x26, 0x23, 0x33, 0x3b, 0x29]
    // "[a](\&amp;)"
    private static let namedDest: [UInt8] = [0x5b, 0x61, 0x5d, 0x28, 0x5c, 0x26, 0x61, 0x6d, 0x70, 0x3b, 0x29]

    func testEscapedAmpersandLeavesNumericReferenceLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"&#3;\"\n      └─ Text \"a\"",
            surface(Self.numericDest))
    }

    func testEscapedAmpersandLeavesEntityReferenceLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"&amp;\"\n      └─ Text \"a\"",
            surface(Self.namedDest))
    }
}
