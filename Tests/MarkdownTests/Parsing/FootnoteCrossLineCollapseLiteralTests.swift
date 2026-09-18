/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Inline structure for a `[^…]` footnote-reference-shaped span that spans a soft line break, with
/// footnotes enabled.
///
/// Ground truth is cmark-gfm. For the fuzzer artifact `[^` U+07F9 `\n` <0xE0→U+FFFD> `]`, cmark collapses
/// the span into a single paragraph text run `[^` U+FFFD `]`; the rewrite produced `[^` U+07F9 `]` instead.
/// Nearby members of this family already match on both sides (`"[^a\nb]"` → `"[^]"`, `"[^a\n<U+FFFD>]"` →
/// `"[^a]"`, `"[^` U+07F9 `\n` U+07F9 `]"` → `"[^]"`), so only this shape diverged.
///
/// cmark's collapse is a reference quirk, so it is reproduced only under `.cmarkBugCompatibility`
/// (flag-on, the fuzzer surface). The shipped deliverable (flag-off) must stay spec-correct: a paragraph
/// with a soft break, both lines preserved. Both assertions use the position-free compare surface.
class FootnoteCrossLineCollapseLiteralTests: XCTestCase {
    // Fuzzer artifact bytes (markdown portion): "[" "^" 0xDF 0xB9 LF 0xE0 "]"
    private static let markdown = String(
        decoding: [0x5b, 0x5e, 0xdf, 0xb9, 0x0a, 0xe0, 0x5d] as [UInt8], as: UTF8.self)
    // Options byte 0xf0, masked to the fuzzable bits (footnotes enabled).
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0xf0 & 0b11011111))

    /// Flag-on reproduces cmark's collapsed literal exactly.
    func testFlagOnMatchesCmarkCollapsedLiteral() {
        var options = Self.fuzzedBits
        options.insert(.cmarkBugCompatibility)

        let expected = "Document\n└─ Paragraph\n   └─ Text \"[^�]\""

        let document = Document(parsing: Self.markdown, options: options)
        XCTAssertEqual(expected, document.debugDescription(options: []))
    }

    /// Flag-off (shipped deliverable) stays spec-correct: a real paragraph with a soft break, both source
    /// lines preserved.
    func testFlagOffStaysSpecCorrect() {
        let options = Self.fuzzedBits  // no cmarkBugCompatibility

        let expected = "Document\n└─ Paragraph\n   ├─ Text \"[^߹\"\n   ├─ SoftBreak\n   └─ Text \"�]\""

        let document = Document(parsing: Self.markdown, options: options)
        XCTAssertEqual(expected, document.debugDescription(options: []))
    }
}
