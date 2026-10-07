/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A backslash before `&` in a fenced code block's info string escapes it (Backslash escapes), so the
/// character reference that follows is literal text.
class FencedInfoStringEntityEscapeOrderTests: XCTestCase {
    private func language(_ bytes: [UInt8]) -> String {
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: ParseOptions(rawValue: 0))
            .debugDescription(options: [])
    }

    // "```" "\" "&#3;"
    private static let numericEntity: [UInt8] = [0x60, 0x60, 0x60, 0x5c, 0x26, 0x23, 0x33, 0x3b]
    // "```" "\" "&amp;"
    private static let namedEntity: [UInt8] = [0x60, 0x60, 0x60, 0x5c, 0x26, 0x61, 0x6d, 0x70, 0x3b]

    func testEscapedAmpersandLeavesNumericReferenceLiteral() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &#3;\n", language(Self.numericEntity))
    }

    func testEscapedAmpersandLeavesEntityReferenceLiteral() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &amp;\n", language(Self.namedEntity))
    }
}
