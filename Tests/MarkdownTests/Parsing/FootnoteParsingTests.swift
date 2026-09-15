/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@_spi(Footnotes) @testable import Markdown

class FootnoteParsingTests: XCTestCase {
    func testSimpleReferenceAndDefinition() {
        let doc = Document(parsing: "see [^a]\n\n[^a]: note\n", options: [.footnotes])
        let expected = """
        Document
        ├─ Paragraph
        │  ├─ Text "see "
        │  └─ FootnoteReference label: "a" index: 1
        └─ FootnoteDefinition label: "a"
           └─ Paragraph
              └─ Text "note"
        """
        XCTAssertEqual(doc.debugDescription(), expected)
    }

    // A footnote definition is a block container: a paragraph inside it continues lazily across a
    // following non-indented line (cmark: def prefix fails, the open paragraph continues).
    func testDefinitionLazyContinuation() {
        let doc = Document(parsing: "[^a]: text\nlazy line\n\nsee [^a]\n", options: [.footnotes])
        let expected = """
        Document
        ├─ Paragraph
        │  ├─ Text "see "
        │  └─ FootnoteReference label: "a" index: 1
        └─ FootnoteDefinition label: "a"
           └─ Paragraph
              ├─ Text "text"
              ├─ SoftBreak
              └─ Text "lazy line"
        """
        XCTAssertEqual(doc.debugDescription(), expected)
    }

    // A blank line then a 4-space-indented block stays inside the definition (multi-block def).
    func testMultiBlockDefinition() {
        let doc = Document(parsing: "[^a]: first\n\n    second para\n\nsee [^a]\n", options: [.footnotes])
        let expected = """
        Document
        ├─ Paragraph
        │  ├─ Text "see "
        │  └─ FootnoteReference label: "a" index: 1
        └─ FootnoteDefinition label: "a"
           ├─ Paragraph
           │  └─ Text "first"
           └─ Paragraph
              └─ Text "second para"
        """
        XCTAssertEqual(doc.debugDescription(), expected)
    }

    // An image-shaped opener `![^a]` is a footnote reference (cmark ignores the image flag here); the
    // `!` stays as literal text.
    func testImageShapedReference() {
        let doc = Document(parsing: "x![^a]\n\n[^a]: note\n", options: [.footnotes])
        let expected = """
        Document
        ├─ Paragraph
        │  ├─ Text "x!"
        │  └─ FootnoteReference label: "a" index: 1
        └─ FootnoteDefinition label: "a"
           └─ Paragraph
              └─ Text "note"
        """
        XCTAssertEqual(doc.debugDescription(), expected)
    }
}
