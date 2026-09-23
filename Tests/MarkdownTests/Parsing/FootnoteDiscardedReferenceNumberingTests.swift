/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(Footnotes) @testable import Markdown
import XCTest

/// A footnote reference that an enclosing footnote-shaped bracket's `.cmarkBugCompatibility` literal
/// reconstruction discards (the inner `[^a]` of `[^ [^a]]`) takes no part in footnote numbering or
/// definition order. cmark-gfm's `process_footnotes` numbers only the references that survive in the
/// finalized tree, in document order, and appends definitions in that index order.
class FootnoteDiscardedReferenceNumberingTests: XCTestCase {
    private func dump(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.footnotes, .cmarkBugCompatibility])
            .debugDescription(options: [])
    }

    func testDiscardedReferenceTakesNoIndex() {
        XCTAssertEqual(
            """
            Document
            ├─ Paragraph
            │  ├─ Text "[^ [^a]] "
            │  └─ FootnoteReference label: "b" index: 1
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  └─ Text "B"
            """,
            dump("[^ [^a]] [^b]\n\n[^a]: A\n\n[^b]: B\n"))
    }

    func testDiscardedReferenceDoesNotOrderDefinitions() {
        XCTAssertEqual(
            """
            Document
            ├─ Paragraph
            │  ├─ Text "[^ [^a]] "
            │  ├─ FootnoteReference label: "b" index: 1
            │  ├─ Text " "
            │  └─ FootnoteReference label: "a" index: 2
            ├─ FootnoteDefinition label: "b"
            │  └─ Paragraph
            │     └─ Text "B"
            └─ FootnoteDefinition label: "a"
               └─ Paragraph
                  └─ Text "A"
            """,
            dump("[^ [^a]] [^b] [^a]\n\n[^a]: A\n\n[^b]: B\n"))
    }

    /// Numbering follows document pre-order over the whole tree with definitions still in place: the
    /// reference inside definition `a` (which opens the document) is numbered first, then the ones
    /// nested in a list inside a block quote, then the trailing one.
    func testReferencesNumberInDocumentPreOrder() {
        XCTAssertEqual(
            """
            Document
            ├─ BlockQuote
            │  └─ UnorderedList
            │     └─ ListItem
            │        └─ Paragraph
            │           ├─ Text "q "
            │           ├─ FootnoteReference label: "c" index: 2
            │           ├─ Text " "
            │           └─ FootnoteReference label: "b" index: 1
            ├─ Paragraph
            │  ├─ Text "text "
            │  └─ FootnoteReference label: "a" index: 3
            ├─ FootnoteDefinition label: "b"
            │  └─ Paragraph
            │     └─ Text "x"
            ├─ FootnoteDefinition label: "c"
            │  └─ Paragraph
            │     └─ Text "y"
            └─ FootnoteDefinition label: "a"
               └─ Paragraph
                  ├─ Text "see "
                  └─ FootnoteReference label: "b" index: 1
            """,
            dump("[^a]: see [^b]\n\n> - q [^c] [^b]\n\n[^b]: x\n\n[^c]: y\n\ntext [^a]\n"))
    }
}
