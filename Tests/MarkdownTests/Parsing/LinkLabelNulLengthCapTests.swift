/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Link-label length cap when the label contains NUL bytes.
///
/// Ground truth is cmark-gfm. cmark measures a link label's length in its NORMALIZED input buffer, where
/// each NUL is replaced by U+FFFD (3 bytes) — so a label of N NULs counts as 3N bytes against cmark's
/// `MAX_LINK_LABEL_LENGTH` (1000; it rejects `> 1000`). The rewrite scanned raw source bytes, counting each
/// NUL as 1, so it accepted a NUL-heavy label cmark rejects. When cmark rejects the label, the `[…]:/l`
/// line is a plain paragraph and a following `=` makes it a setext heading; the rewrite instead registered
/// a reference definition and resolved a link. cmark's byte (not character) counting is a reference quirk
/// (the spec counts characters, so a U+FFFD is 1), so flag-on reproduces it (NUL counts 3) while flag-off
/// stays spec-correct (NUL counts 1). Position-free compare surface.
class LinkLabelNulLengthCapTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: 0)
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// `[` + NUL×count + `]:/l` LF `=`
    private func input(nulCount: Int) -> [UInt8] {
        [0x5b] + Array(repeating: 0x00, count: nulCount) + [0x5d, 0x3a, 0x2f, 0x6c, 0x0a, 0x3d]
    }

    /// 334 NULs = 1002 normalized bytes > 1000: flag-on must reject the label (matching cmark), so the
    /// line stays a paragraph and the `=` makes a setext H1 whose text is the literal bracket run.
    func testOverCapLabelRejectedFlagOn() {
        let expected = "Document\n└─ Heading level: 1\n   └─ Text \"[" + String(repeating: "\u{FFFD}", count: 334) + "]:/l\""
        XCTAssertEqual(expected, surface(input(nulCount: 334), cmarkBugCompatible: true))
    }

    /// Flag-off (spec-correct): 334 U+FFFD characters ≤ 999, so the label is valid — the reference
    /// definition registers and the `=` is its own paragraph.
    func testOverCapLabelValidFlagOff() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"=\"",
            surface(input(nulCount: 334), cmarkBugCompatible: false))
    }

    /// 333 NULs = 999 normalized bytes ≤ 1000: the label is valid in BOTH flag states (guards against
    /// over-rejecting at the boundary) — the definition registers, the `=` is a paragraph.
    func testAtCapLabelValidBothFlags() {
        let expected = "Document\n└─ Paragraph\n   └─ Text \"=\""
        XCTAssertEqual(expected, surface(input(nulCount: 333), cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(input(nulCount: 333), cmarkBugCompatible: false))
    }
}
