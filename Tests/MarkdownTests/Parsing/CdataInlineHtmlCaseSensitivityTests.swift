/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A CDATA section begins with the string `<![CDATA[` (Raw HTML), so a keyword in any other case is text.
class CdataInlineHtmlCaseSensitivityTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let options = ParseOptions(rawValue: UInt(0x0a & 0b11011111))
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    // "-<![CDaTA[]]>"; the leading `-` keeps the line from starting an HTML block.
    private static let mixed: [UInt8] = [0x2d, 0x3c, 0x21, 0x5b, 0x43, 0x44, 0x61, 0x54, 0x41, 0x5b, 0x5d, 0x5d, 0x3e]
    // "-<![CDATA[]]>"
    private static let upper: [UInt8] = [0x2d, 0x3c, 0x21, 0x5b, 0x43, 0x44, 0x41, 0x54, 0x41, 0x5b, 0x5d, 0x5d, 0x3e]

    func testMixedCaseKeywordIsText() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"-<![CDaTA[]]>\"",
            surface(Self.mixed))
    }

    func testUppercaseKeywordIsInlineHtml() {
        let expected = "Document\n└─ Paragraph\n   ├─ Text \"-\"\n   └─ InlineHTML <![CDATA[]]>"
        XCTAssertEqual(expected, surface(Self.upper))
    }
}
