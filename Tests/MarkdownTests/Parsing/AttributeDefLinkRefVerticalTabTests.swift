/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A link reference `[baz]` left on an attribute-definition line by a vertical tab that ends the
/// definition's attribute list, with a matching forward reference definition.
///
/// Ground truth is cmark-gfm. For `^[baz]:/` VT `[baz]` / (blank) / `[baz]:/`, the VT terminates the
/// attribute definition's attributes after `/`, leaving `[baz]` as content on that line. cmark does NOT
/// resolve that `[baz]` against the forward reference definition `[baz]:/` — it stays literal `Text
/// "[baz]"`. The rewrite resolved it to a link. (Without the VT, `^[baz]:/[baz]` is a single attribute
/// definition consuming the whole line — an empty document on both sides; the divergence needs the
/// attribute def with attributes, the VT, and the forward ref def together.)
///
/// This asserts only the flag-on (fuzzer) surface: it must match cmark's literal.
class AttributeDefLinkRefVerticalTabTests: XCTestCase {
    // "^[baz]:/" VT "[baz]" LF LF "[baz]:/"
    private static let bytes: [UInt8] = [
        0x5e, 0x5b, 0x62, 0x61, 0x7a, 0x5d, 0x3a, 0x2f, 0x0b, 0x5b, 0x62, 0x61, 0x7a, 0x5d,
        0x0a, 0x0a, 0x5b, 0x62, 0x61, 0x7a, 0x5d, 0x3a, 0x2f,
    ]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x6f & 0b11011111))

    func testFlagOnKeepsLinkReferenceLiteral() {
        var options = Self.fuzzedBits
        options.insert(.cmarkBugCompatibility)
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"[baz]\"",
            Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
                .debugDescription(options: []))
    }
}
