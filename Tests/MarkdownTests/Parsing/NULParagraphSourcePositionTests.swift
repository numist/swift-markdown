/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A NUL is replaced with U+FFFD (Insecure characters), and source positions count it as its one source byte.
/// Each expected tree is the tree for the same input with every NUL replaced by a one-byte letter, apart from
/// that text.
class NULParagraphSourcePositionTests: XCTestCase {
    private func positions(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    func testNULParagraphTextHasRange() {
        XCTAssertEqual("Document @1:1-3:2\n├─ Paragraph @1:1-1:4\n│  └─ Text @1:1-1:4 \"a\u{fffd}b\"\n└─ Paragraph @3:1-3:2\n   └─ Text @3:1-3:2 \"c\"", positions("a\u{0}b\n\nc"))
    }

    func testInlineAfterNULHasRange() {
        XCTAssertEqual("Document @1:1-1:6\n└─ Paragraph @1:1-1:6\n   ├─ Text @1:1-1:3 \"\u{fffd}x\"\n   └─ Emphasis @1:3-1:6\n      └─ Text @1:4-1:5 \"y\"", positions("\u{0}x*y*"))
    }

    func testATXHeading() {
        XCTAssertEqual("Document @1:1-1:6\n└─ Heading @1:1-1:6 level: 1\n   └─ Text @1:3-1:6 \"a\u{fffd}b\"", positions("# a\u{0}b"))
    }

    func testSetextHeading() {
        XCTAssertEqual("Document @1:1-2:4\n└─ Heading @1:1-2:4 level: 1\n   └─ Text @1:1-1:4 \"a\u{fffd}b\"", positions("a\u{0}b\n==="))
    }

    func testSetextHeadingInBlockQuote() {
        XCTAssertEqual("Document @1:1-3:6\n└─ BlockQuote @1:1-3:6\n   └─ Heading @1:3-3:6 level: 1\n      ├─ Text @1:3-1:4 \"a\"\n      ├─ SoftBreak\n      └─ Text @2:3-2:6 \"b\u{fffd}c\"", positions("> a\n> b\u{0}c\n> ==="))
    }

    func testTableCells() {
        XCTAssertEqual("Document @1:1-3:12\n└─ Table @1:1-3:12 alignments: |-|-|\n   ├─ Head @1:1-1:11\n   │  ├─ Cell @1:2-1:6\n   │  │  └─ Text @1:3-1:5 \"a\u{fffd}\"\n   │  └─ Cell @1:7-1:10\n   │     └─ Text @1:8-1:9 \"b\"\n   └─ Body @3:1-3:12\n      └─ Row @3:1-3:12\n         ├─ Cell @3:2-3:7\n         │  └─ Text @3:3-3:6 \"c\u{fffd}d\"\n         └─ Cell @3:8-3:11\n            └─ Text @3:9-3:10 \"e\"", positions("| a\u{0} | b |\n|---|---|\n| c\u{0}d | e |"))
    }

    func testTableCellWithEscapedPipe() {
        XCTAssertEqual("Document @1:1-2:6\n└─ Table @1:1-2:6 alignments: |-|-|\n   ├─ Head @1:1-1:9\n   │  ├─ Cell @1:2-1:6\n   │  │  └─ Text @1:2-1:6 \"\u{fffd}|a\"\n   │  └─ Cell @1:7-1:8\n   │     └─ Text @1:7-1:8 \"b\"\n   └─ Body", positions("|\u{0}\\|a|b|\n|-|-|"))
    }

    func testTablePrecedingParagraph() {
        XCTAssertEqual("Document @1:1-3:10\n├─ Paragraph @1:1-1:3\n│  └─ Text @1:1-1:3 \"x\u{fffd}\"\n└─ Table @2:1-3:10 alignments: |-|-|\n   ├─ Head @2:1-2:10\n   │  ├─ Cell @2:2-2:5\n   │  │  └─ Text @2:3-2:4 \"a\"\n   │  └─ Cell @2:6-2:9\n   │     └─ Text @2:7-2:8 \"b\"\n   └─ Body", positions("x\u{0}\n| a | b |\n|---|---|"))
    }

    func testNestedTablePrecedingParagraph() {
        XCTAssertEqual("Document @1:1-4:8\n└─ BlockQuote @1:1-4:8\n   ├─ Paragraph @1:3-2:5\n   │  ├─ Text @1:3-1:4 \"p\"\n   │  ├─ SoftBreak\n   │  └─ Text @2:3-2:5 \"q\u{fffd}\"\n   └─ Table @3:3-4:8 alignments: |-|\n      ├─ Head @3:3-3:8\n      │  └─ Cell @3:4-3:7\n      │     └─ Text @3:5-3:6 \"a\"\n      └─ Body", positions("> p\n> q\u{0}\n> | a |\n> |---|"))
    }

    func testMultiLineParagraph() {
        XCTAssertEqual("Document @1:1-2:4\n└─ Paragraph @1:1-2:4\n   ├─ Text @1:1-1:2 \"p\"\n   ├─ SoftBreak\n   └─ Text @2:1-2:4 \"q\u{fffd}r\"", positions("p\nq\u{0}r"))
    }

    func testMultiLineBlockQuoteParagraph() {
        XCTAssertEqual("Document @1:1-2:6\n└─ BlockQuote @1:1-2:6\n   └─ Paragraph @1:3-2:6\n      ├─ Text @1:3-1:4 \"p\"\n      ├─ SoftBreak\n      └─ Text @2:3-2:6 \"q\u{fffd}r\"", positions("> p\n> q\u{0}r"))
    }

    func testListItemWithTabAfterMarker() {
        XCTAssertEqual("Document @1:1-1:6\n└─ UnorderedList @1:1-1:6\n   └─ ListItem @1:1-1:6\n      └─ Paragraph @1:3-1:6\n         └─ Text @1:3-1:6 \"a\u{fffd}b\"", positions("-\ta\u{0}b"))
    }

    func testBlockQuoteWithTabAfterMarker() {
        XCTAssertEqual("Document @1:1-1:6\n└─ BlockQuote @1:1-1:6\n   └─ Paragraph @1:3-1:6\n      └─ Text @1:3-1:6 \"a\u{fffd}b\"", positions(">\ta\u{0}b"))
    }

    func testTaskListItem() {
        XCTAssertEqual("Document @1:1-1:10\n└─ UnorderedList @1:1-1:10\n   └─ ListItem @1:1-1:10 checkbox: [ ]\n      └─ Paragraph @1:7-1:10\n         └─ Text @1:7-1:10 \"a\u{fffd}b\"", positions("- [ ] a\u{0}b"))
    }

    func testCodeSpan() {
        XCTAssertEqual("Document @1:1-1:6\n└─ Paragraph @1:1-1:6\n   └─ InlineCode @1:1-1:6 `a\u{fffd}b`", positions("`a\u{0}b`"))
    }

    func testLinkText() {
        XCTAssertEqual("Document @1:1-1:9\n└─ Paragraph @1:1-1:9\n   └─ Link @1:1-1:9 destination: \"u\"\n      └─ Text @1:2-1:5 \"a\u{fffd}b\"", positions("[a\u{0}b](u)"))
    }

    func testTableCellWithNULAfterEscapedPipe() {
        XCTAssertEqual("Document @1:1-2:4\n└─ Table @1:1-2:4 alignments: |-|\n   ├─ Head @1:1-1:10\n   │  └─ Cell @1:2-1:9\n   │     └─ Text @1:3-1:8 \"f|\u{fffd}\u{fffd}\"\n   └─ Body", positions("| f\\|\u{0}\u{0} |\n|-|"))
    }

    func testTablePrecedingParagraphWithNULAfterEscapedPipe() {
        XCTAssertEqual("Document @1:1-3:4\n├─ Paragraph @1:1-1:6\n│  └─ Text @1:1-1:6 \"x|\u{fffd}y\"\n└─ Table @2:1-3:4 alignments: |-|\n   ├─ Head @2:1-2:6\n   │  └─ Cell @2:2-2:5\n   │     └─ Text @2:3-2:4 \"a\"\n   └─ Body", positions("x\\|\u{0}y\n| a |\n|-|"))
    }

    /// A `\|` leaves the source columns of the text after it unchanged, on its own line and the next.
    func testTablePrecedingParagraphEscapeKeepsColumns() {
        XCTAssertEqual("Document @1:1-4:4\n├─ Paragraph @1:1-2:3\n│  ├─ Text @1:1-1:5 \"x|y\"\n│  ├─ SoftBreak\n│  └─ Text @2:1-2:3 \"zz\"\n└─ Table @3:1-4:4 alignments: |-|\n   ├─ Head @3:1-3:6\n   │  └─ Cell @3:2-3:5\n   │     └─ Text @3:3-3:4 \"a\"\n   └─ Body", positions("x\\|y\nzz\n| a |\n|-|"))
    }

    func testNestedTablePrecedingParagraphWithNULAfterEscapedPipe() {
        XCTAssertEqual("Document @1:1-4:6\n└─ BlockQuote @1:1-4:6\n   ├─ Paragraph @1:3-2:5\n   │  ├─ Text @1:3-1:7 \"x|\u{fffd}\"\n   │  ├─ SoftBreak\n   │  └─ Text @2:3-2:5 \"y\u{fffd}\"\n   └─ Table @3:3-4:6 alignments: |-|\n      ├─ Head @3:3-3:8\n      │  └─ Cell @3:4-3:7\n      │     └─ Text @3:5-3:6 \"a\"\n      └─ Body", positions("> x\\|\u{0}\n> y\u{0}\n> | a |\n> |-|"))
    }
}
