/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Inline structure for a backslash-escaped-caret `[\^…]` (and its image form `![\^…]`) footnote-shaped
/// bracket that spans a soft line break, with footnotes enabled.
///
/// Ground truth is cmark-gfm. When the captured label's raw byte cut lands mid-character, cmark's slice
/// truncates the multi-byte scalar and its `String(cString:)` bridge repairs the tail to a single U+FFFD,
/// so the collapsed run is `[^` U+FFFD `]`. This is the escaped-caret twin of the plain `[^…]` case
/// (see `FootnoteCrossLineCollapseLiteralTests`). Flag-on reproduces cmark's quirk; flag-off stays
/// spec-correct (a paragraph with a soft break, both source lines preserved). Position-free compare surface.
class EscapedCaretFootnoteCrossLineLiteralTests: XCTestCase {
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0xf0 & 0b11011111))
    private static let flagOnExpected = "Document\n└─ Paragraph\n   └─ Text \"[^�]\""

    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        let markdown = String(decoding: bytes, as: UTF8.self)
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    /// `[` `\` `^` U+07F9 LF <0xE0→U+FFFD> `]`: a two-byte scalar truncated to its lead byte by the cut.
    func testEscapedCaretTwoByteScalar() {
        let bytes: [UInt8] = [0x5b, 0x5c, 0x5e, 0xdf, 0xb9, 0x0a, 0xe0, 0x5d]
        XCTAssertEqual(Self.flagOnExpected, surface(bytes, cmarkBugCompatible: true))
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"[^߹\"\n   ├─ SoftBreak\n   └─ Text \"�]\"",
            surface(bytes, cmarkBugCompatible: false))
    }

    /// The image form `![\^…]` collapses the same way flag-on.
    func testEscapedCaretImageForm() {
        let bytes: [UInt8] = [0x21, 0x5b, 0x5c, 0x5e, 0xdf, 0xb9, 0x0a, 0xe0, 0x5d]
        XCTAssertEqual(Self.flagOnExpected, surface(bytes, cmarkBugCompatible: true))
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"![^߹\"\n   ├─ SoftBreak\n   └─ Text \"�]\"",
            surface(bytes, cmarkBugCompatible: false))
    }

    /// A four-byte scalar (U+1F600) truncated by the cut repairs to one U+FFFD too.
    func testEscapedCaretFourByteScalar() {
        let bytes: [UInt8] = [0x5b, 0x5c, 0x5e, 0xf0, 0x9f, 0x98, 0x80, 0x0a, 0xe0, 0x5d]
        XCTAssertEqual(Self.flagOnExpected, surface(bytes, cmarkBugCompatible: true))
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"[^😀\"\n   ├─ SoftBreak\n   └─ Text \"�]\"",
            surface(bytes, cmarkBugCompatible: false))
    }
}
