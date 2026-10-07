/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A GFM table header row that is a whitespace-only leading cell closed by a pipe (`<ws>|`), with table
/// spans on. Ground truth is cmark-gfm.
///
/// Only a lazy continuation line keeps its leading whitespace in cmark's paragraph content (a matched
/// continuation or a paragraph's first line is advanced to its first non-space), so only there does the
/// header row carry a whitespace-only first cell. cmark's `row_from_string` marks a cell as a colspan
/// filler when its trimmed buffer is empty AND `start_offset == end_offset`; for that first cell
/// `end_offset = start_offset + cell_matched - 1`, so the filler test holds for exactly ONE whitespace
/// byte (` |`, `\t|` → `Cell colspan: 0`) and fails for two or more (`  |` → plain `Cell`).
class TableLazyWhitespaceHeaderCellTests: XCTestCase {
    /// Options byte 0x0a (smart off, symbol links; tables and table spans always on in the harness).
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var bytes = Array(markdown.utf8)
        bytes.append(0x0a)
        let (text, fuzzedOptions) = FuzzRegressionTests.splitInput(bytes)!
        var options = fuzzedOptions
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: text, options: options).debugDescription(options: [])
    }

    private static func quotedTable(headCell: String) -> String {
        "Document\n└─ BlockQuote\n   ├─ Paragraph\n   │  └─ Text \"x\"\n   └─ Table alignments: |-|\n      ├─ Head\n      │  └─ \(headCell)\n      └─ Body"
    }

    func testLazyOneSpaceIsColspanFiller() {
        XCTAssertEqual(Self.quotedTable(headCell: "Cell colspan: 0"), surface(">x\n |\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the space
    /// and opens a table headed by a filler cell.
    func testLazyOneSpaceFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n |\n>-|\n", cmarkBugCompatible: false))
    }

    func testLazyTwoSpacesIsPlainCell() {
        XCTAssertEqual(Self.quotedTable(headCell: "Cell"), surface(">x\n  |\n>-|\n"))
    }

    func testLazyThreeSpacesIsPlainCell() {
        XCTAssertEqual(Self.quotedTable(headCell: "Cell"), surface(">x\n   |\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the
    /// spaces and opens a table headed by a whitespace cell.
    func testLazyThreeSpacesFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n   |\n>-|\n", cmarkBugCompatible: false))
    }

    func testLazyTabIsColspanFiller() {
        XCTAssertEqual(Self.quotedTable(headCell: "Cell colspan: 0"), surface(">x\n\t|\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the tab
    /// and opens a table headed by a filler cell.
    func testLazyTabFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n\t|\n>-|\n", cmarkBugCompatible: false))
    }

    func testLazySpaceTabIsPlainCell() {
        XCTAssertEqual(Self.quotedTable(headCell: "Cell"), surface(">x\n \t|\n>-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the space
    /// and tab and opens a table headed by a whitespace cell.
    func testLazySpaceTabFlagOff() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n \t|\n>-|\n", cmarkBugCompatible: false))
    }

    private static func listQuotedTable(headCell: String) -> String {
        "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  └─ Text \"x\"\n         └─ Table alignments: |-|\n            ├─ Head\n            │  └─ \(headCell)\n            └─ Body"
    }

    /// The list item's content indent consumes the two spaces whole, leaving the lazy residual a single tab byte.
    func testLazyTabAfterListIndentIsColspanFiller() {
        XCTAssertEqual(Self.listQuotedTable(headCell: "Cell colspan: 0"), surface("- >x\n  \t|\n  >-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the tab
    /// and opens a table headed by a filler cell.
    func testLazyTabAfterListIndentFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            ├─ Text \"|\"\n            ├─ SoftBreak\n            └─ Text \"-|\"", surface("- >x\n  \t|\n  >-|\n", cmarkBugCompatible: false))
    }

    /// The list item's content indent partially consumes the tab (`partially_consumed_tab`), and `add_line`
    /// emits its two leftover columns as spaces: a two-byte whitespace cell, so a plain `Cell`.
    func testLazySplitTabAfterListIndentIsPlainCell() {
        XCTAssertEqual(Self.listQuotedTable(headCell: "Cell"), surface("- >x\n \t|\n  >-|\n"))
    }

    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the tab's
    /// leftover columns and opens a table headed by a whitespace cell.
    func testLazySplitTabAfterListIndentFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            ├─ Text \"|\"\n            ├─ SoftBreak\n            └─ Text \"-|\"", surface("- >x\n \t|\n  >-|\n", cmarkBugCompatible: false))
    }

    /// A matched block-quote continuation is advanced to its first non-space, so the header is a lone
    /// `|` (zero columns) and no table forms.
    func testNonLazyContinuationFormsNoTable() {
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"",
            surface(">x\n>  |\n>-|\n"))
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", surface(">x\n>  |\n>-|\n", cmarkBugCompatible: false))
    }

    /// A paragraph's first line is advanced to its first non-space, so the header is a lone `|`.
    func testTopLevelLeadingSpacesFormNoTable() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"|\"\n   ├─ SoftBreak\n   └─ Text \"-|\"",
            surface("  |\n-|\n"))
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"|\"\n   ├─ SoftBreak\n   └─ Text \"-|\"", surface("  |\n-|\n", cmarkBugCompatible: false))
    }

    /// A pipe-preceded whitespace-only cell backs `start_offset` over the whitespace to the previous pipe,
    /// so it is never zero-width: a plain `Cell`.
    func testMiddleWhitespaceCellIsPlainCell() {
        XCTAssertEqual(
            "Document\n└─ Table alignments: |-|-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  ├─ Cell\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body",
            surface("a|  |b\n-|-|-\n"))
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  ├─ Cell\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body", surface("a|  |b\n-|-|-\n", cmarkBugCompatible: false))
    }

    /// Flag-off (shipped) drops the lazy residual, so the header is a lone `|` and no table forms.
    func testLazyTwoSpacesFlagOff() {
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"",
            surface(">x\n  |\n>-|\n", cmarkBugCompatible: false))
    }
}
