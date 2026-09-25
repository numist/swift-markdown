/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A footnote definition continues past a short-indented line only when that raw line is empty (flag-ON).
///
/// Ground truth is cmark-gfm (flag-ON). `parse_footnote_definition_block_prefix` keeps a definition open on a
/// line indented less than 4 columns only if the line's first raw byte is its terminator, so a whitespace-only
/// line (or a blank line behind a container prefix like `>`) closes the definition and the indented content
/// that follows lands in the enclosing container. Flag-OFF follows CommonMark: any whitespace-only line is
/// blank and keeps the definition open. Position-free compare surface.
class EmptyFootnoteDefinitionWhitespaceLineTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        var options = ParseOptions(rawValue: UInt(0xf0 & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testTabOnlyLineInListItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ CodeBlock language: none\n           \"", surface("- [^a]:\n\t\n\t\t\""))
    }

    func testSpaceOnlyLineInListItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ CodeBlock language: none\n           \"", surface("- [^a]:\n \n\t\t\""))
    }

    func testCarriageReturnThenTabLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ CodeBlock language: none\n           \"", surface("- [^a]:\r\t\n\t\t\""))
    }

    func testFuzzedArtifactNULLabel() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ CodeBlock language: none\n           \"", surface("- [^\u{0}]:\r\t\n\t\t\""))
    }

    func testSpaceIndentedCode() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ CodeBlock language: none\n         x", surface("- [^a]:\n\t\n      x"))
    }

    func testBlockQuote() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ CodeBlock language: none\n        x", surface("> [^a]:\n>\t\n>\t\tx"))
    }

    func testReferencedDefinitionStaysEmpty() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n│          x\n├─ Paragraph\n│  └─ FootnoteReference label: \"a\" index: 1\n└─ FootnoteDefinition label: \"a\"", surface("- [^a]:\n\t\n\t\tx\n\n[^a]"))
    }

    func testEmptyLineControl() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem", surface("- [^a]:\n\n\t\t\""))
    }

    func testOrderedListItem() {
        XCTAssertEqual("Document\n└─ OrderedList\n   └─ ListItem\n      └─ CodeBlock language: none\n         x", surface("1. [^a]:\n \n       x"))
    }

    func testNestedListItems() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ UnorderedList\n         └─ ListItem\n            └─ CodeBlock language: none\n               x", surface("- - [^a]:\n \n        x"))
    }

    func testBlockQuoteInListItem() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ CodeBlock language: none\n            x", surface("- > [^a]:\n  >\n  >     x"))
    }

    /// A top-level whitespace-only line of 1-3 spaces closes the definition; 4 spaces reach its content column and continue it.
    func testTopLevelSpaceOnlyLines() {
        for spaces in 1...3 {
            XCTAssertEqual("Document\n├─ CodeBlock language: none\n│  x\n├─ Paragraph\n│  └─ FootnoteReference label: \"a\" index: 1\n└─ FootnoteDefinition label: \"a\"", surface("[^a]:\n" + String(repeating: " ", count: spaces) + "\n    x\n\n[^a]"), "\(spaces) spaces")
        }
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"a\" index: 1\n└─ FootnoteDefinition label: \"a\"\n   └─ Paragraph\n      └─ Text \"x\"", surface("[^a]:\n    \n    x\n\n[^a]"))
    }

    func testNonEmptyDefinitionClosesBeforeIndentedContent() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n│          y\n├─ Paragraph\n│  └─ FootnoteReference label: \"a\" index: 1\n└─ FootnoteDefinition label: \"a\"\n   └─ Paragraph\n      └─ Text \"x\"", surface("- [^a]: x\n \n\t\ty\n\n[^a]"))
    }

    func testParagraphAfterWhitespaceLineControl() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"y\"", surface("- [^a]: x\n \n  y"))
    }

    func testCRLFEmptyLineKeepsDefinitionOpen() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem", surface("- [^a]:\r\n\r\n\t\t\""))
    }

    func testCRLFSpaceOnlyLineClosesDefinition() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ CodeBlock language: none\n           \"", surface("- [^a]:\r\n \r\n\t\t\""))
    }

    /// Flag-OFF (spec-correct): a whitespace-only line is a blank line, so the definition continues past it.
    func testSpecCorrectDefinitionContinuesPastWhitespaceLine() {
        let document = Document(parsing: "- [^a]:\n \n      x\n\n[^a]", options: ParseOptions(rawValue: UInt(0xf0 & 0b11011111)))
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n├─ Paragraph\n│  └─ FootnoteReference label: \"a\" index: 1\n└─ FootnoteDefinition label: \"a\"\n   └─ Paragraph\n      └─ Text \"x\"", document.debugDescription(options: []))
    }
}
