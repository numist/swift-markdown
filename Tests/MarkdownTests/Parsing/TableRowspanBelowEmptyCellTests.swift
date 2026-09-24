/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A `^` row-span cell below a cell the table padded in for a short row does not give that padded cell a row span.
///
/// Ground truth is cmark-gfm. A body row with fewer cells than the table has columns (`x`, or `x|`, whose
/// trailing pipe ends the row after one cell) is padded out, and cmark gives padded cells no span data: the
/// `^` below still stops at the padded cell and prints as `rowspan: 0` with its marker cleared, but the padded
/// cell never grows. A cell parsed from the source — non-empty, whitespace-only, or a zero-width `||` colspan
/// filler — does grow. Flag-off (shipped) the padded cell grows like any other. Position-free compare surface.
class TableRowspanBelowEmptyCellTests: XCTestCase {
    private func surface(_ bytes: [UInt8], optionBits: UInt8) -> String {
        var options = ParseOptions(rawValue: UInt(optionBits & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    private static let emptyAboveCaret = "Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"x\"\n      │  └─ Cell\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"y\"\n         └─ Cell rowspan: 0"

    func testPaddedCellAboveCaret() {
        XCTAssertEqual(Self.emptyAboveCaret, surface(Array("a|b\n-|-\nx\ny|^".utf8), optionBits: 0x7c))
    }

    func testExplicitEmptyCellAboveCaret() {
        XCTAssertEqual(Self.emptyAboveCaret, surface(Array("a|b\n-|-\nx|\ny|^".utf8), optionBits: 0x7c))
    }

    func testNonEmptyCellAboveCaretControl() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"x\"\n      │  └─ Cell rowspan: 3\n      │     └─ Text \"z\"\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"y\"\n      │  └─ Cell rowspan: 0\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"w\"\n         └─ Cell rowspan: 0", surface(Array("a|b\n-|-\nx|z\ny|^\nw|^".utf8), optionBits: 0x7c))
    }

    // The fuzzer artifact: "||" NUL LF "-|-" LF NUL LF 0xFF "|^" (options byte 0x7c).
    func testFuzzedArtifact() {
        let bytes: [UInt8] = [0x7c, 0x7c, 0x00, 0x0a, 0x2d, 0x7c, 0x2d, 0x0a, 0x00, 0x0a, 0xff, 0x7c, 0x5e]
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell colspan: 0\n   │  └─ Cell\n   │     └─ Text \"\u{fffd}\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"\u{fffd}\"\n      │  └─ Cell\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"\u{fffd}\"\n         └─ Cell rowspan: 0", surface(bytes, optionBits: 0x7c))
    }

    private func surfaceFlagOff(_ markdown: String) -> String {
        Document(parsing: markdown, options: ParseOptions(rawValue: UInt(0x7c & 0b11011111)))
            .debugDescription(options: [])
    }

    func testPaddedCellAboveSeveralCarets() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"x\"\n      │  └─ Cell\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"y\"\n      │  └─ Cell rowspan: 0\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"w\"\n         └─ Cell rowspan: 0", surface(Array("a|b\n-|-\nx\ny|^\nw|^".utf8), optionBits: 0x7c))
    }

    /// A padded cell interrupts a span: the `^` below it stops there, so the spanning cell above keeps its earlier span.
    func testPaddedCellInterruptsEarlierSpan() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"x\"\n      │  └─ Cell rowspan: 2\n      │     └─ Text \"z\"\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"y\"\n      │  └─ Cell rowspan: 0\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"w\"\n      │  └─ Cell\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"v\"\n         └─ Cell rowspan: 0", surface(Array("a|b\n-|-\nx|z\ny|^\nw\nv|^".utf8), optionBits: 0x7c))
    }

    func testSeveralPaddedCellsAboveCarets() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  ├─ Cell\n   │  │  └─ Text \"b\"\n   │  └─ Cell\n   │     └─ Text \"c\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"x\"\n      │  ├─ Cell\n      │  └─ Cell\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"y\"\n         ├─ Cell rowspan: 0\n         └─ Cell rowspan: 0", surface(Array("a|b|c\n-|-|-\nx\ny|^|^".utf8), optionBits: 0x7c))
    }

    /// A parsed cell that is empty (here whitespace-only, in the header) is a real cell, so it does grow.
    func testParsedEmptyHeaderCellAboveCaretGrows() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell rowspan: 2\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      └─ Row\n         ├─ Cell rowspan: 0\n         └─ Cell\n            └─ Text \"x\"", surface(Array("| |b\n-|-\n^|x".utf8), optionBits: 0x7c))
    }

    /// A zero-width `||` colspan filler is a parsed cell, so a `^` below it grows it; a padded cell beside it does not.
    func testColspanFillerAboveCaretGrowsButPaddedCellDoesNot() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  ├─ Cell\n   │  │  └─ Text \"b\"\n   │  └─ Cell\n   │     └─ Text \"c\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell colspan: 2\n      │  │  └─ Text \"x\"\n      │  ├─ Cell colspan: 0 rowspan: 2\n      │  └─ Cell\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"y\"\n         ├─ Cell rowspan: 0\n         └─ Cell rowspan: 0", surface(Array("a|b|c\n-|-|-\nx||\ny|^|^".utf8), optionBits: 0x7c))
    }

    /// Flag-off (shipped): the padded cell absorbs the span below it, as a parsed cell would.
    func testPaddedCellAboveCaretGrowsFlagOff() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"x\"\n      │  └─ Cell rowspan: 2\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"y\"\n         └─ Cell rowspan: 0", surfaceFlagOff("a|b\n-|-\nx\ny|^"))
    }
    /// Flag-off (shipped): a padded cell still stops the upward scan, and grows instead of the cell above it.
    func testPaddedCellInterruptsEarlierSpanFlagOff() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"x\"\n      │  └─ Cell rowspan: 2\n      │     └─ Text \"z\"\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"y\"\n      │  └─ Cell rowspan: 0\n      ├─ Row\n      │  ├─ Cell\n      │  │  └─ Text \"w\"\n      │  └─ Cell rowspan: 2\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"v\"\n         └─ Cell rowspan: 0", surfaceFlagOff("a|b\n-|-\nx|z\ny|^\nw\nv|^"))
    }

    /// Flag-off (shipped): both the colspan filler and the padded cell beside it grow.
    func testColspanFillerAndPaddedCellAboveCaretsGrowFlagOff() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  ├─ Cell\n   │  │  └─ Text \"b\"\n   │  └─ Cell\n   │     └─ Text \"c\"\n   └─ Body\n      ├─ Row\n      │  ├─ Cell colspan: 2\n      │  │  └─ Text \"x\"\n      │  ├─ Cell colspan: 0 rowspan: 2\n      │  └─ Cell rowspan: 2\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"y\"\n         ├─ Cell rowspan: 0\n         └─ Cell rowspan: 0", surfaceFlagOff("a|b|c\n-|-|-\nx||\ny|^|^"))
    }
}
