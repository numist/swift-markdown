/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Order of entity resolution vs backslash-escape processing in a fenced code block's info string.
///
/// Ground truth is cmark-gfm. For a fence followed by `\&#3;` cmark resolves the entity FIRST
/// (`&#3;` → U+0003) and only then applies backslash escapes, so the info string is `\` + U+0003; for
/// `\&amp;` it is `\&amp;` → (entity) `\&` → (escape) `&`. Standard CommonMark inline processing is a single
/// left-to-right pass where the `\` escapes the `&`, leaving `&#3;` / `&amp;` as literal text. cmark's
/// entity-first order is a reference quirk specific to the info string, so flag-on reproduces it while
/// flag-off stays spec-correct (the `\` escapes the `&`). Escaped `\u{…}` literals keep the invisible
/// U+0003 explicit. Position-free compare surface.
class FencedInfoStringEntityEscapeOrderTests: XCTestCase {
    private func language(_ bytes: [UInt8], cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: 0)
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    // "```" "\" "&#3;"
    private static let numericEntity: [UInt8] = [0x60, 0x60, 0x60, 0x5c, 0x26, 0x23, 0x33, 0x3b]
    // "```" "\" "&amp;"
    private static let namedEntity: [UInt8] = [0x60, 0x60, 0x60, 0x5c, 0x26, 0x61, 0x6d, 0x70, 0x3b]

    /// Flag-on: entity resolved first, so `\&#3;` → `\` + U+0003 (matching cmark).
    func testNumericEntityResolvedFirstFlagOn() {
        XCTAssertEqual("Document\n└─ CodeBlock language: \\\u{3}\n", language(Self.numericEntity, cmarkBugCompatible: true))
    }

    /// Flag-off (spec-correct): the `\` escapes the `&`, so `&#3;` stays literal.
    func testNumericEntityEscapedFirstFlagOff() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &#3;\n", language(Self.numericEntity, cmarkBugCompatible: false))
    }

    /// Flag-on: `\&amp;` → (entity) `\&` → (escape) `&` (matching cmark).
    func testNamedEntityResolvedFirstFlagOn() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &\n", language(Self.namedEntity, cmarkBugCompatible: true))
    }

    /// Flag-off (spec-correct): the `\` escapes the `&`, so `&amp;` stays literal.
    func testNamedEntityEscapedFirstFlagOff() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &amp;\n", language(Self.namedEntity, cmarkBugCompatible: false))
    }
}
