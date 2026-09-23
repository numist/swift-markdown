/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// An escaped-caret image footnote `![\^…]` inside an ATX heading.
///
/// Ground truth is cmark-gfm. For `# ![\^` <0xFF→U+FFFD> `]` cmark's `[^[` collapse reduces the heading
/// text to `[^` U+FFFD `]` (dropping the image `!`). The rewrite's flag-on collapse instead produced a
/// spurious `[^` U+FFFD `]` + newline + `]`. The divergence needs the image `![` form in a heading (the
/// link `[` form and the non-heading form both already match; the U+FFFD is incidental — a plain `x`
/// diverges too). Flag-on reproduces cmark's collapsed text; flag-off stays spec-correct (`![^` U+FFFD `]`,
/// the escaped-caret image kept literal). Position-free compare surface.
class EscapedCaretImageFootnoteHeadingTests: XCTestCase {
    // "# ![\^" 0xFF "]"
    private static let bytes: [UInt8] = [0x23, 0x20, 0x21, 0x5b, 0x5c, 0x5e, 0xff, 0x5d]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0xff & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// Flag-on: cmark's collapsed heading text, image `!` dropped, no spurious trailing bytes.
    func testFlagOnMatchesCollapsedText() {
        XCTAssertEqual(
            "Document\n└─ Heading level: 1\n   └─ Text \"[^�]\"",
            surface(cmarkBugCompatible: true))
    }

    /// Flag-off (spec-correct): the escaped-caret image is kept literal, including its `!`.
    func testFlagOffKeepsLiteral() {
        XCTAssertEqual(
            "Document\n└─ Heading level: 1\n   └─ Text \"![^�]\"",
            surface(cmarkBugCompatible: false))
    }
}
