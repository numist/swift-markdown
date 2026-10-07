/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// An escaped-caret image `![\^…]` inside a GFM table cell.
///
/// Ground truth is cmark-gfm (flag-ON). cmark's escaped-caret image over-read runs past the cell content;
/// a table cell's inline buffer ends in its NUL terminator (like an ATX heading's, FINDINGS #202), so the
/// reference's `String(cString:)` bridge truncates there and the cell shows `[^…]` with nothing after it.
/// The same holds for the paragraph split off before a table's header; a setext heading, like a paragraph,
/// keeps its trailing newline. The non-image `[\^a]` form over-reads only onto the `]` (control). Position-free compare surface.
class EscapedCaretImageInTableCellTests: XCTestCase {
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var options = ParseOptions(rawValue: UInt(0xe4 & 0b11011111))
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private static func singleColumn(_ cellText: String) -> String {
        "Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body\n      └─ Row\n         └─ Cell\n            └─ Text \"\(cellText)\""
    }

    func testFuzzedArtifact() {
        XCTAssertEqual(Self.singleColumn("[^\u{14}]"), surface("o\n|-\n![\\^\u{14}]"))
    }

    func testPlainLabel() {
        XCTAssertEqual(Self.singleColumn("[^a]"), surface("o\n|-\n![\\^a]"))
    }

    func testPipedCell() {
        XCTAssertEqual(Self.singleColumn("[^a]"), surface("o\n|-\n|![\\^a]|"))
    }

    func testTextBeforeImage() {
        XCTAssertEqual(Self.singleColumn("x [^ab]"), surface("o\n|-\nx ![\\^ab]"))
    }

    func testFollowingCell() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"o\"\n   │  └─ Cell\n   │     └─ Text \"p\"\n   └─ Body\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"[^a]\"\n         └─ Cell\n            └─ Text \"b\"", surface("o|p\n-|-\n![\\^a]|b"))
    }

    func testFollowingRow() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body\n      ├─ Row\n      │  └─ Cell\n      │     └─ Text \"[^\u{14}]\"\n      └─ Row\n         └─ Cell\n            └─ Text \"q\"", surface("o\n|-\n![\\^\u{14}]\nq"))
    }

    func testNonImageControl() {
        XCTAssertEqual(Self.singleColumn("[^a]]"), surface("o\n|-\n[\\^a]"))
    }

    func testHeaderRowCell() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"[^a]\"\n   └─ Body", surface("![\\^a]\n|-"))
    }

    func testHeaderRowMiddleCell() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"[^a]\"\n   │  └─ Cell\n   │     └─ Text \"p\"\n   └─ Body", surface("![\\^a]|p\n-|-"))
    }

    func testLastOfTwoCells() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"o\"\n   │  └─ Cell\n   │     └─ Text \"p\"\n   └─ Body\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"b\"\n         └─ Cell\n            └─ Text \"[^a]\"", surface("o|p\n-|-\nb|![\\^a]"))
    }

    /// cmark's feed-time NUL→U+FFFD runs before the cell buffer is built, so the capture ends on the
    /// buffer's own terminator right after the `]`.
    func testNULInCell() {
        XCTAssertEqual(Self.singleColumn("[^\u{FFFD}]"), surface("o\n|-\n![\\^\u{0}]"))
    }

    /// `unescape_pipes` rewrites the cell buffer before inline parsing; the capture still ends on its terminator.
    func testEscapedPipeInCell() {
        XCTAssertEqual(Self.singleColumn("[^a|]"), surface("o\n|-\n![\\^a\\|]"))
    }

    /// The lines before a table's header become a paragraph built from a trimmed, NUL-terminated buffer
    /// (`try_inserting_table_header_paragraph`), not from newline-terminated lines.
    func testParagraphBeforeTable() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ Text \"x [^a]\"\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body", surface("x ![\\^a]\no\n|-"))
    }

    /// A setext heading keeps its content line's trailing newline, so the capture over-reads into it, as in a paragraph.
    func testSetextHeadingKeepsNewline() {
        XCTAssertEqual("Document\n└─ Heading level: 1\n   └─ Text \"[^a]\n]\"", surface("![\\^a]\n==="))
    }

    func testParagraphBeforeTableInBlockQuote() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   ├─ Paragraph\n   │  └─ Text \"x [^a]\"\n   └─ Table alignments: |-|\n      ├─ Head\n      │  └─ Cell\n      │     └─ Text \"o\"\n      └─ Body", surface("> x ![\\^a]\n> o\n> |-"))
    }

    func testParagraphBeforeTableWithCRLF() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ Text \"x [^a]\"\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body", surface("x ![\\^a]\r\no\r\n|-"))
    }

    /// The preceding paragraph's buffer is trimmed, so trailing whitespace doesn't stand between the `]` and the terminator.
    func testParagraphBeforeTableWithTrailingTab() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ Text \"x [^a]\"\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body", surface("x ![\\^a]\t\no\n|-"))
    }

    /// Flag-off, a backslash-escaped caret makes `![\^…]` plain text, so the brackets stay literal with the image
    /// `!` kept and nothing read past the `]`, whereas cmark-gfm drops the `!` and over-reads past the label.
    func testEscapedCaretStaysLiteralWithoutBugCompatibility() {
        let cases: [(markdown: String, expected: String)] = [
            ("o\n|-\n![\\^\u{14}]", Self.singleColumn("![^\u{14}]")),
            ("o\n|-\n![\\^a]", Self.singleColumn("![^a]")),
            ("o\n|-\n|![\\^a]|", Self.singleColumn("![^a]")),
            ("o\n|-\nx ![\\^ab]", Self.singleColumn("x ![^ab]")),
            ("o|p\n-|-\n![\\^a]|b", "Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"o\"\n   │  └─ Cell\n   │     └─ Text \"p\"\n   └─ Body\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"![^a]\"\n         └─ Cell\n            └─ Text \"b\""),
            ("o\n|-\n![\\^\u{14}]\nq", "Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body\n      ├─ Row\n      │  └─ Cell\n      │     └─ Text \"![^\u{14}]\"\n      └─ Row\n         └─ Cell\n            └─ Text \"q\""),
            ("o\n|-\n[\\^a]", Self.singleColumn("[^a]")),
            ("![\\^a]\n|-", "Document\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"![^a]\"\n   └─ Body"),
            ("![\\^a]|p\n-|-", "Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"![^a]\"\n   │  └─ Cell\n   │     └─ Text \"p\"\n   └─ Body"),
            ("o|p\n-|-\nb|![\\^a]", "Document\n└─ Table alignments: |-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"o\"\n   │  └─ Cell\n   │     └─ Text \"p\"\n   └─ Body\n      └─ Row\n         ├─ Cell\n         │  └─ Text \"b\"\n         └─ Cell\n            └─ Text \"![^a]\""),
            ("o\n|-\n![\\^\u{0}]", Self.singleColumn("![^\u{FFFD}]")),
            ("o\n|-\n![\\^a\\|]", Self.singleColumn("![^a|]")),
            ("x ![\\^a]\no\n|-", "Document\n├─ Paragraph\n│  └─ Text \"x ![^a]\"\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body"),
            ("![\\^a]\n===", "Document\n└─ Heading level: 1\n   └─ Text \"![^a]\""),
            ("> x ![\\^a]\n> o\n> |-", "Document\n└─ BlockQuote\n   ├─ Paragraph\n   │  └─ Text \"x ![^a]\"\n   └─ Table alignments: |-|\n      ├─ Head\n      │  └─ Cell\n      │     └─ Text \"o\"\n      └─ Body"),
            ("x ![\\^a]\r\no\r\n|-", "Document\n├─ Paragraph\n│  └─ Text \"x ![^a]\"\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body"),
            ("x ![\\^a]\t\no\n|-", "Document\n├─ Paragraph\n│  └─ Text \"x ![^a]\"\n└─ Table alignments: |-|\n   ├─ Head\n   │  └─ Cell\n   │     └─ Text \"o\"\n   └─ Body"),
        ]
        for (markdown, expected) in cases {
            XCTAssertEqual(expected, surface(markdown, cmarkBugCompatible: false), markdown.debugDescription)
        }
    }
}
