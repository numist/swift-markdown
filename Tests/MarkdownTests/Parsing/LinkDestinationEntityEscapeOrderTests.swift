/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Order of entity resolution vs backslash-escape processing in a LINK DESTINATION — the sibling of the
/// fenced info-string case (`FencedInfoStringEntityEscapeOrderTests`).
///
/// Ground truth is cmark-gfm. `cmark_clean_url` (`inlines.c`) uses the same two-pass order as the fenced
/// info string: entities are decoded first, then backslash escapes are stripped. So `[a](\&#3;)` yields a
/// destination `\` + U+0003, and `[a](\&amp;)` yields `&`. Standard CommonMark single-pass escaping (a `\`
/// escaping the following `&`) instead leaves `&#3;` / `&amp;` literal. cmark's entity-first order is a
/// reference quirk, so flag-on reproduces it while flag-off stays spec-correct. Link titles do NOT diverge
/// (they match on both sides); only the destination does. Escaped `\u{…}` keeps the invisible U+0003
/// explicit. Position-free compare surface.
class LinkDestinationEntityEscapeOrderTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: 0)
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    // "[a](\&#3;)"
    private static let numericDest: [UInt8] = [0x5b, 0x61, 0x5d, 0x28, 0x5c, 0x26, 0x23, 0x33, 0x3b, 0x29]
    // "[a](\&amp;)"
    private static let namedDest: [UInt8] = [0x5b, 0x61, 0x5d, 0x28, 0x5c, 0x26, 0x61, 0x6d, 0x70, 0x3b, 0x29]

    /// Flag-on: entity resolved first, so `\&#3;` → destination `\` + U+0003 (matching cmark).
    func testNumericDestResolvedFirstFlagOn() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"\\\u{3}\"\n      └─ Text \"a\"",
            surface(Self.numericDest, cmarkBugCompatible: true))
    }

    /// Flag-off (spec-correct): the `\` escapes the `&`, so `&#3;` stays literal.
    func testNumericDestEscapedFirstFlagOff() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"&#3;\"\n      └─ Text \"a\"",
            surface(Self.numericDest, cmarkBugCompatible: false))
    }

    /// Flag-on: `\&amp;` → (entity) `\&` → (escape) `&` (matching cmark).
    func testNamedDestResolvedFirstFlagOn() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"&\"\n      └─ Text \"a\"",
            surface(Self.namedDest, cmarkBugCompatible: true))
    }

    /// Flag-off (spec-correct): the `\` escapes the `&`, so `&amp;` stays literal.
    func testNamedDestEscapedFirstFlagOff() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"&amp;\"\n      └─ Text \"a\"",
            surface(Self.namedDest, cmarkBugCompatible: false))
    }
}
