/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(InlineOnly) @testable import Markdown
import XCTest

/// Inline-only parsing reports line-aware source positions, like block parsing does.
///
/// In `a` LF `b *c*` the text on the second line starts at line 2, column 1 (UTF-8 byte columns, as
/// everywhere else in the deliverable), and the document and its single paragraph span the whole input.
class InlineOnlySourcePositionTests: XCTestCase {
    private func positions(_ markdown: String, _ options: ParseOptions) -> String {
        Document(parsing: markdown, options: options).debugDescription(options: .printSourceLocations)
    }

    func testSecondLineTextIsOnLineTwo() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:6\n└─ Paragraph @1:1-2:6\n   ├─ Text @1:1-2:3 \"a\nb \"\n   └─ Emphasis @2:3-2:6\n      └─ Text @2:4-2:5 \"c\"", positions("a\nb *c*", mode))
        }
    }

    func testBackslashHardBreakAcrossLines() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:2\n└─ Paragraph @1:1-2:2\n   ├─ Text @1:1-1:2 \"a\"\n   ├─ LineBreak\n   └─ Text @2:1-2:2 \"b\"", positions("a\\\nb", mode))
        }
    }

    /// A CRLF is normalized to one `\n` in the content but still occupies two source bytes, so line 2 starts after both.
    func testCRLFLineEnding() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:6\n└─ Paragraph @1:1-2:6\n   ├─ Text @1:1-2:3 \"a\nb \"\n   └─ Emphasis @2:3-2:6\n      └─ Text @2:4-2:5 \"c\"", positions("a\r\nb *c*", mode))
            // The normalized `\n` images the LF, so text ending at a CRLF covers both bytes and ends at the next line's start...
            XCTAssertEqual("Document @1:1-2:4\n└─ Paragraph @1:1-2:4\n   ├─ Text @1:1-2:1 \"a\n\"\n   └─ Emphasis @2:1-2:4\n      └─ Text @2:2-2:3 \"b\"", positions("a\r\n*b*", mode))
            // ...while text starting at a CRLF starts at its LF, one byte past the CR.
            XCTAssertEqual("Document @1:1-2:2\n└─ Paragraph @1:1-2:2\n   ├─ Emphasis @1:1-1:4\n   │  └─ Text @1:2-1:3 \"a\"\n   └─ Text @1:5-2:2 \"\nb\"", positions("*a*\r\nb", mode))
        }
    }

    /// A lone CR ends a line just like LF does.
    func testLoneCRLineEnding() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:6\n└─ Paragraph @1:1-2:6\n   ├─ Text @1:1-2:3 \"a\nb \"\n   └─ Emphasis @2:3-2:6\n      └─ Text @2:4-2:5 \"c\"", positions("a\rb *c*", mode))
        }
    }

    /// A NUL is one source byte even though it surfaces as the three-byte U+FFFD.
    func testNUL() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-1:8\n└─ Paragraph @1:1-1:8\n   ├─ Text @1:1-1:5 \"a\u{FFFD}b \"\n   └─ Emphasis @1:5-1:8\n      └─ Text @1:6-1:7 \"c\"", positions("a\u{0}b *c*", mode))
        }
    }

    /// A NUL ending the input, after a CRLF: the U+FFFD text ends at the source's last byte, not two bytes past it.
    func testTrailingNULAfterCRLF() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:5\n└─ Paragraph @1:1-2:5\n   ├─ Text @1:1-2:1 \"a\n\"\n   ├─ Emphasis @2:1-2:4\n   │  └─ Text @2:2-2:3 \"b\"\n   └─ Text @2:4-2:5 \"\u{FFFD}\"", positions("a\r\n*b*\u{0}", mode))
        }
    }

    /// A leading byte-order mark is skipped: line 1's columns count from the byte after it.
    func testLeadingByteOrderMark() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:2\n└─ Paragraph @1:1-2:2\n   └─ Text @1:1-2:2 \"a\nb\"", positions("\u{FEFF}a\nb", mode))
            XCTAssertEqual("Document @1:1-2:2\n└─ Paragraph @1:1-2:2\n   └─ Text @1:1-2:2 \"a\nb\"", positions("\u{FEFF}a\r\nb", mode))
        }
    }

    /// A BOM-only input's empty paragraph sits at the start of line 1, past the BOM; a blank line after the BOM ends just past its line ending.
    func testByteOrderMarkWithoutContent() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1\n└─ Paragraph @1:1", positions("\u{FEFF}", mode))
            XCTAssertEqual("Document @1:1-1:2\n└─ Paragraph @1:1-1:2\n   └─ Text @1:1-1:2 \"\n\"", positions("\u{FEFF}\n", mode))
        }
    }

    /// Blank lines and a trailing line ending are literal paragraph content, so the paragraph and document span them; the input's end sits just past the final line ending, on the last line.
    func testBlankLinesAndTrailingLineEnding() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-3:5\n└─ Paragraph @1:1-3:5\n   └─ Text @1:1-3:5 \"a\n\n  b\n\"", positions("a\n\n  b\n", mode))
        }
    }

    /// Columns are UTF-8 byte offsets, so a two-byte scalar on line 2 advances the column by two.
    func testMultibyteScalarOnSecondLine() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:7\n└─ Paragraph @1:1-2:7\n   ├─ Text @1:1-2:4 \"a\n\u{E9} \"\n   └─ Emphasis @2:4-2:7\n      └─ Text @2:5-2:6 \"c\"", positions("a\n\u{E9} *c*", mode))
        }
    }

    /// Leading reference definitions are consumed from the normalized CRLF content; what remains keeps its original-source positions.
    func testLeadingReferenceDefinitionWithCRLF() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-3:4\n└─ Paragraph @1:1-3:4\n   ├─ Text @2:2-3:1 \"\n\"\n   └─ Link @3:1-3:4 destination: \"/u\"\n      └─ Text @3:2-3:3 \"a\"", positions("[a]: /u\r\n\r\n[a]", mode))
        }
    }

    func testLinkSpanningLines() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            XCTAssertEqual("Document @1:1-2:6\n└─ Paragraph @1:1-2:6\n   └─ Link @1:1-2:6 destination: \"u\"\n      └─ Text @1:2-2:2 \"a\nb\"", positions("[a\nb](u)", mode))
        }
    }
}
