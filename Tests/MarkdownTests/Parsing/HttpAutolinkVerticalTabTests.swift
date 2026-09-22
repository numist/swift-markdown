/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A bare `http://` (no domain) immediately followed by a vertical tab, with GFM autolinks on.
///
/// Ground truth is cmark-gfm. cmark forms an extended autolink from the domain-less `http://` only when a
/// vertical tab (U+000B) terminates it — a space, newline, or end-of-input leaves it as literal text on
/// both sides, and a real domain (`http://x`) autolinks on both sides. So the bare-`http://`-before-VT
/// autolink is a cmark quirk (a domain-less URL is not a valid GFM autolink). Flag-on reproduces it
/// (an empty leading `Text` then the `Link`); flag-off stays spec-correct (literal text). Position-free surface.
class HttpAutolinkVerticalTabTests: XCTestCase {
    // "http://" VT
    private static let bytes: [UInt8] = [0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x0b]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x62 & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// Flag-on: the domain-less `http://` autolinks, matching cmark.
    func testBareHttpAutolinksBeforeVerticalTabFlagOn() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"\"\n   └─ Link destination: \"http://\u{b}\"\n      └─ Text \"http://\u{b}\"",
            surface(cmarkBugCompatible: true))
    }

    /// Flag-off (shipped): a domain-less `http://` is not a valid autolink — it stays literal text.
    func testBareHttpStaysTextFlagOff() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"http://\u{b}\"",
            surface(cmarkBugCompatible: false))
    }
}
