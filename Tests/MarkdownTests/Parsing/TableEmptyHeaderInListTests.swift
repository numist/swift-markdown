/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A GFM table with an EMPTY header row (a lone `|`) inside a list item, following a paragraph line.
///
/// Ground truth is cmark-gfm. For `- [` / ` |` / `  -|` (tables on) cmark splits the list item into a
/// paragraph `[` and a degenerate table — an empty header row becomes a `Cell colspan: 0` and `-|` is the
/// delimiter. cmark does NOT do this at top level (`[` / `|` / `-|` stays two paragraphs on both sides);
/// the degenerate table forms only in the list context, an inconsistency it applies nowhere else. So
/// flag-on reproduces cmark's degenerate table; flag-off stays consistent with the top-level / spec
/// behavior — one paragraph, no table. Position-free compare surface.
class TableEmptyHeaderInListTests: XCTestCase {
    // "- [" LF " |" LF "  -|"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x5b, 0x0a, 0x20, 0x7c, 0x0a, 0x20, 0x20, 0x2d, 0x7c]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x47 & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// Flag-on: the empty-header degenerate table forms inside the list item, matching cmark.
    func testEmptyHeaderTableFormsFlagOn() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      ├─ Paragraph\n      │  └─ Text \"[\"\n      └─ Table alignments: |-|\n         ├─ Head\n         │  └─ Cell colspan: 0\n         └─ Body",
            surface(cmarkBugCompatible: true))
    }

    /// Flag-off (shipped): no table — the three lines stay one paragraph (consistent with the top-level
    /// case, where the same empty-header shape forms no table on either side).
    func testNoTableFlagOff() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"[\"\n         ├─ SoftBreak\n         ├─ Text \"|\"\n         ├─ SoftBreak\n         └─ Text \"-|\"",
            surface(cmarkBugCompatible: false))
    }
}
