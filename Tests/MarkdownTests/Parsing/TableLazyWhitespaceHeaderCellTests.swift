/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A GFM table header row that is a whitespace-only leading cell closed by a pipe (`<ws>|`), with table
/// spans on. Ground truth is cmark-gfm.
class TableLazyWhitespaceHeaderCellTests: XCTestCase {
    /// Options byte 0x0a (smart off, symbol links; tables and table spans always on in the harness).
    private func surface(_ markdown: String) -> String {
        var bytes = Array(markdown.utf8)
        bytes.append(0x0a)
        let (text, options) = FuzzRegressionTests.splitInput(bytes)!
        return Document(parsing: text, options: options).debugDescription(options: [])
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the space
    /// and opens a table headed by a filler cell.
    func testLazyOneSpaceFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n |\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the
    /// spaces and opens a table headed by a whitespace cell.
    func testLazyThreeSpacesFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n   |\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the tab
    /// and opens a table headed by a filler cell.
    func testLazyTabFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n\t|\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the space
    /// and tab and opens a table headed by a whitespace cell.
    func testLazySpaceTabFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n \t|\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the tab
    /// and opens a table headed by a filler cell.
    func testLazyTabAfterListIndentFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            ├─ Text \"|\"\n            ├─ SoftBreak\n            └─ Text \"-|\"", surface("- >x\n  \t|\n  >-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the tab's
    /// leftover columns and opens a table headed by a whitespace cell.
    func testLazySplitTabAfterListIndentFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            ├─ Text \"|\"\n            ├─ SoftBreak\n            └─ Text \"-|\"", surface("- >x\n \t|\n  >-|\n"))
    }

    /// A matched block-quote continuation is advanced to its first non-space, so the header is a lone
    /// `|` (zero columns) and no table forms.
    func testNonLazyContinuationFormsNoTable() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n>  |\n>-|\n"))
    }

    /// A paragraph's first line is advanced to its first non-space, so the header is a lone `|`.
    func testTopLevelLeadingSpacesFormNoTable() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"|\"\n   ├─ SoftBreak\n   └─ Text \"-|\"", surface("  |\n-|\n"))
    }

    /// A pipe-preceded whitespace-only cell backs `start_offset` over the whitespace to the previous pipe,
    /// so it is never zero-width: a plain `Cell`.
    func testMiddleWhitespaceCellIsPlainCell() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  ├─ Cell\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body", surface("a|  |b\n-|-|-\n"))
    }

    /// Flag-off (shipped) drops the lazy residual, so the header is a lone `|` and no table forms.
    func testLazyTwoSpacesFlagOff() {
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"",
            surface(">x\n  |\n>-|\n"))
    }
}
