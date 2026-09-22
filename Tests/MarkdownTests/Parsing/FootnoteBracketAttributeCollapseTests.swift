/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// The `[^[` footnote collapse over a `^[…]` inline-attribute span whose following `(…)` link destination
/// contains a newline.
///
/// Ground truth is cmark-gfm. For `[^^[](` newline `)]` (footnotes on) cmark collapses the whole span to a
/// single literal text run that preserves every source byte, `[^^[](` newline `)]`. The rewrite instead
/// collapsed it to `[^]`, dropping the `^[](` newline `)` middle. Flag-on reproduces cmark's collapsed
/// literal; flag-off stays spec-correct — the `^[…]` inline-attribute structure, both source lines
/// preserved. Position-free compare surface.
class FootnoteBracketAttributeCollapseTests: XCTestCase {
    // "[^^[](" LF ")]"
    private static let bytes: [UInt8] = [0x5b, 0x5e, 0x5e, 0x5b, 0x5d, 0x28, 0x0a, 0x29, 0x5d]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0xf7 & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// Flag-on: the collapse reconstructs the full literal, matching cmark.
    func testFlagOnReconstructsFullLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"[^^[](\n)]\"",
            surface(cmarkBugCompatible: true))
    }

    /// Flag-off (shipped): the spec-correct inline-attribute structure, both source lines preserved.
    func testFlagOffKeepsInlineAttributes() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineAttributes attributes: `\n`\n   └─ Text \"]\"",
            surface(cmarkBugCompatible: false))
    }
}
