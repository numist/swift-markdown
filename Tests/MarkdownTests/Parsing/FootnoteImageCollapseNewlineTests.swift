/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// The `[^[` footnote collapse over an image `![](…)` whose link destination contains a line ending.
///
/// Ground truth is cmark-gfm. For `[^![](` CR `)]` (footnotes on) cmark collapses the whole span into a
/// single literal text run, preserving every byte with the CR normalized to LF (`[^![](` LF `)]`). The
/// rewrite over-collapsed to `[^]`, dropping the `![](…)` middle. This is the image sibling of #190 (which
/// covered the `^[…]` inline-attribute payload): a line ending swallowed by a matched inline construct
/// (here an image destination) must not reset the collapsed footnote's captured-label measurement. Flag-on
/// reproduces cmark's collapsed literal; flag-off stays spec-correct (the `![…]` image structure).
/// Position-free surface.
class FootnoteImageCollapseNewlineTests: XCTestCase {
    // "[^![](" CR ")]"
    private static let bytes: [UInt8] = [0x5b, 0x5e, 0x21, 0x5b, 0x5d, 0x28, 0x0d, 0x29, 0x5d]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x8d & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// Flag-on: the collapse reconstructs the full literal (CR normalized to LF), matching cmark.
    func testFlagOnReconstructsFullLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"[^![](\n)]\"",
            surface(cmarkBugCompatible: true))
    }

    /// Flag-off (shipped): the spec-correct image structure, both source lines preserved.
    func testFlagOffKeepsImage() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ Image \n   └─ Text \"]\"",
            surface(cmarkBugCompatible: false))
    }
}
