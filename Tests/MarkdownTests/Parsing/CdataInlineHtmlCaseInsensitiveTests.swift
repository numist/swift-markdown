/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Inline HTML recognition of a CDATA section whose `CDATA` keyword is not uppercase.
///
/// The CommonMark spec requires a CDATA section to begin with the literal
/// uppercase `<![CDATA[`. Flag-off stays spec-correct (only uppercase `CDATA` is inline HTML, mixed case stays literal text).
/// The leading `-` keeps the construct inline rather than opening an HTML block. Position-free surface.
class CdataInlineHtmlCaseInsensitiveTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let options = ParseOptions(rawValue: UInt(0x0a & 0b11011111))
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    // "-<![CDaTA[]]>"  (mixed-case keyword)
    private static let mixed: [UInt8] = [0x2d, 0x3c, 0x21, 0x5b, 0x43, 0x44, 0x61, 0x54, 0x41, 0x5b, 0x5d, 0x5d, 0x3e]
    // "-<![CDATA[]]>"  (canonical uppercase)
    private static let upper: [UInt8] = [0x2d, 0x3c, 0x21, 0x5b, 0x43, 0x44, 0x41, 0x54, 0x41, 0x5b, 0x5d, 0x5d, 0x3e]

    /// Flag-off (shipped): the mixed-case keyword stays literal text (spec requires uppercase `CDATA`).
    func testMixedCaseKeywordStaysTextFlagOff() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"-<![CDaTA[]]>\"",
            surface(Self.mixed))
    }

    /// The canonical uppercase keyword is inline HTML in BOTH flag states (spec-correct and cmark agree).
    func testUppercaseKeywordIsInlineHtmlBothFlags() {
        let expected = "Document\n└─ Paragraph\n   ├─ Text \"-\"\n   └─ InlineHTML <![CDATA[]]>"
        XCTAssertEqual(expected, surface(Self.upper))
    }
}
