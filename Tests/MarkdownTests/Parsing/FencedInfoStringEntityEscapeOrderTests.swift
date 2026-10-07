/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Order of entity resolution vs backslash-escape processing in a fenced code block's info string.
///
/// Standard CommonMark inline processing is a single
/// left-to-right pass where the `\` escapes the `&`, leaving `&#3;` / `&amp;` as literal text. Flag-off stays
/// spec-correct (the `\` escapes the `&`). Position-free compare surface.
class FencedInfoStringEntityEscapeOrderTests: XCTestCase {
    private func language(_ bytes: [UInt8]) -> String {
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: ParseOptions(rawValue: 0))
            .debugDescription(options: [])
    }

    // "```" "\" "&#3;"
    private static let numericEntity: [UInt8] = [0x60, 0x60, 0x60, 0x5c, 0x26, 0x23, 0x33, 0x3b]
    // "```" "\" "&amp;"
    private static let namedEntity: [UInt8] = [0x60, 0x60, 0x60, 0x5c, 0x26, 0x61, 0x6d, 0x70, 0x3b]

    /// Flag-off (spec-correct): the `\` escapes the `&`, so `&#3;` stays literal.
    func testNumericEntityEscapedFirstFlagOff() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &#3;\n", language(Self.numericEntity))
    }

    /// Flag-off (spec-correct): the `\` escapes the `&`, so `&amp;` stays literal.
    func testNamedEntityEscapedFirstFlagOff() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &amp;\n", language(Self.namedEntity))
    }
}
