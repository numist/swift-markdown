/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A `^` row-span cell preceded by a vertical tab or form feed is still a row-span marker.
///
/// Ground truth is cmark-gfm. In each case the body row's last cell is `^` with a leading VT/FF (and no
/// trailing pipe); cmark treats it as a row-span marker (`rowspan: 0`) and grows the cell above to
/// `rowspan: 2`. Position-free compare surface.
class TableRowspanCaretAfterVerticalWhitespaceTests: XCTestCase {
    private func surface(_ bytes: [UInt8], optionBits: UInt8 = 0x7c) -> String {
        var options = ParseOptions(rawValue: UInt(optionBits & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    private static let singleColumn = "Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell rowspan: 2\n   │     └─ Text \"a\"\n   └─ Body\n      └─ Row\n         └─ Cell rowspan: 0"

    func testVerticalTabBeforeCaret() {
        XCTAssertEqual(Self.singleColumn, surface(Array("a\n|-\n|\u{0B}^".utf8)))
    }

    func testFormFeedBeforeCaret() {
        XCTAssertEqual(Self.singleColumn, surface(Array("a\n|-\n|\u{0C}^".utf8)))
    }

    func testMixedWhitespaceBeforeCaret() {
        XCTAssertEqual(Self.singleColumn, surface(Array("a\n|-\n|\u{0B}\u{0C} ^".utf8)))
    }

    func testVerticalTabBeforeCaretInSecondColumn() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell rowspan: 2\n   │     └─ Text \"b\"\n   └─ Body\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"x\"\n         └─ Cell rowspan: 0", surface(Array("a|b\n-|-\nx|\u{0B}^".utf8)))
    }

    func testVerticalTabBeforeCaretWithClosingPipe() {
        XCTAssertEqual(Self.singleColumn, surface(Array("a\n|-\n|\u{0B}^|".utf8)))
    }

    func testFormFeedBeforeCaretWithPaddedClosingPipe() {
        XCTAssertEqual(Self.singleColumn, surface(Array("a\n|-\n|\u{0C}^ |".utf8)))
    }

    func testVerticalTabBeforeCaretInFirstColumnOfTwo() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell rowspan: 2\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      └─ Row\n         ├─ Cell rowspan: 0\n         └─ Cell\n            └─ Text \"x\"", surface(Array("a|b\n-|-\n|\u{0B}^|x".utf8)))
    }

    // A header cell has no row above to span into, so it keeps its `^` text but still carries rowspan 0.
    func testVerticalTabBeforeCaretInHeader() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell rowspan: 0\n   │     └─ Text \"^\"\n   └─ Body", surface(Array("|\u{0B}^|\n|-|".utf8)))
    }

    // The row's first cell with no leading pipe is not pipe-preceded, so its leading VT is content, not padding.
    func testVerticalTabBeforeCaretWithoutLeadingPipeStaysLiteral() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"\u{0B}^\"\n         └─ Cell\n            └─ Text \"x\"", surface(Array("a|b\n-|-\n\u{0B}^|x".utf8)))
    }

    // A trailing VT is content (only a pipe's leading padding absorbs VT/FF), so `^<VT>` is not a marker.
    func testVerticalTabAfterCaretStaysLiteral() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"a\"\n   └─ Body\n      └─ Row\n         └─ Cell\n            └─ Text \"^\u{0B}\"", surface(Array("a\n|-\n|^\u{0B}".utf8)))
    }

    func testVerticalTabBeforeCaretFlagOff() {
        let options = ParseOptions(rawValue: UInt(0x7c & 0b11011111))
        XCTAssertFalse(options.contains(.cmarkBugCompatibility))
        XCTAssertEqual(Self.singleColumn, Document(parsing: "a\n|-\n|\u{0B}^", options: options).debugDescription(options: []))
    }

    // The fuzzer artifact: 0xFF LF "|-" LF "|" VT "^" (options byte 0x7c).
    func testFuzzedArtifact() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell rowspan: 2\n   │     └─ Text \"\u{fffd}\"\n   └─ Body\n      └─ Row\n         └─ Cell rowspan: 0", surface([0xff, 0x0a, 0x7c, 0x2d, 0x0a, 0x7c, 0x0b, 0x5e]))
    }
}
