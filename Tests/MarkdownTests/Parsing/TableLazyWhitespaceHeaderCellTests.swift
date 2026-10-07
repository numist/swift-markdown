/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A table header row whose first cell is only whitespace before a pipe (`<ws>|`). A lazy continuation
/// line loses its initial whitespace like any paragraph line (Paragraphs), so the header row is a lone `|`
/// and no table forms (Tables (extension)).
class TableLazyWhitespaceHeaderCellTests: XCTestCase {
    /// Parses `markdown` with `[.parseSymbolLinks, .parseMinimalDoxygen]`.
    private func tree(_ markdown: String) -> String {
        var bytes = Array(markdown.utf8)
        bytes.append(0x0a)
        let (text, options) = DocumentRegressionTests.splitInput(bytes)!
        return Document(parsing: text, options: options).debugDescription(options: [])
    }

    func testLazyOneSpace() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", tree(">x\n |\n>-|\n"))
    }

    func testLazyThreeSpaces() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", tree(">x\n   |\n>-|\n"))
    }

    func testLazyTab() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", tree(">x\n\t|\n>-|\n"))
    }

    func testLazySpaceTab() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", tree(">x\n \t|\n>-|\n"))
    }

    func testLazyTabAfterListIndent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            ├─ Text \"|\"\n            ├─ SoftBreak\n            └─ Text \"-|\"", tree("- >x\n  \t|\n  >-|\n"))
    }

    func testLazySplitTabAfterListIndent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            ├─ SoftBreak\n            ├─ Text \"|\"\n            ├─ SoftBreak\n            └─ Text \"-|\"", tree("- >x\n \t|\n  >-|\n"))
    }

    /// A non-lazy line in a block quote also loses its initial whitespace.
    func testNonLazyContinuationFormsNoTable() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", tree(">x\n>  |\n>-|\n"))
    }

    /// A paragraph's first line also loses its initial whitespace.
    func testTopLevelLeadingSpacesFormNoTable() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"|\"\n   ├─ SoftBreak\n   └─ Text \"-|\"", tree("  |\n-|\n"))
    }

    /// A whitespace-only cell between two pipes is an empty cell.
    func testMiddleWhitespaceCellIsEmptyCell() {
        XCTAssertEqual("Document\n└─ Table alignments: |-|-|-|\n   ├─ Head\n   │  ├─ Cell\n   │  │  └─ Text \"a\"\n   │  ├─ Cell\n   │  └─ Cell\n   │     └─ Text \"b\"\n   └─ Body", tree("a|  |b\n-|-|-\n"))
    }

    func testLazyTwoSpaces() {
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"",
            tree(">x\n  |\n>-|\n"))
    }
}
