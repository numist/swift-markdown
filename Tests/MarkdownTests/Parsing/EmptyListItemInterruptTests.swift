/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A list marker that opens an *empty* first item cannot interrupt a paragraph (CommonMark 0.31 §5.2).
///
/// Emptiness is decided by the run of spaces / tabs after the marker: if only whitespace remains
/// before the line ends, the item is empty and the marker folds back into the paragraph as text. The
/// whole trailing-whitespace run counts, not just the first byte - `*  ` (two spaces) and `*\t` (a tab
/// materialized to several spaces) are as empty as `* `. The no-interrupt rule applies only while a
/// paragraph is open; a marker on its own line still opens an empty list.
class EmptyListItemInterruptTests: XCTestCase {
    /// Two trailing spaces after the marker leave the item empty, so it does not interrupt the open
    /// paragraph: the `*` folds back in as text joined by a soft break.
    func testEmptyItemWithTrailingSpacesDoesNotInterruptParagraph() {
        let text = "a\n*  "

        let expectedDump = """
        Document @1:1-2:4
        └─ Paragraph @1:1-2:4
           ├─ Text @1:1-1:2 "a"
           ├─ SoftBreak
           └─ Text @2:1-2:2 "*"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// A non-empty first item still interrupts the paragraph and opens a list.
    func testNonEmptyItemInterruptsParagraph() {
        let text = "a\n* b"

        let expectedDump = """
        Document @1:1-2:4
        ├─ Paragraph @1:1-1:2
        │  └─ Text @1:1-1:2 "a"
        └─ UnorderedList @2:1-2:4
           └─ ListItem @2:1-2:4
              └─ Paragraph @2:3-2:4
                 └─ Text @2:3-2:4 "b"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// The whole trailing whitespace run counts toward emptiness, not just the first few: six trailing
    /// spaces (past the 5-column indent boundary) still leave the item empty, so it does not interrupt.
    func testManyTrailingSpacesStillEmptyAndDoesNotInterruptParagraph() {
        let text = "a\n*      "

        let expectedDump = """
        Document @1:1-2:8
        └─ Paragraph @1:1-2:8
           ├─ Text @1:1-1:2 "a"
           ├─ SoftBreak
           └─ Text @2:1-2:2 "*"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Five or more spaces followed by real content is a non-empty item (an indented code block within
    /// the item), so it still interrupts the paragraph and opens a list.
    func testFivePlusSpacesThenContentInterruptsAsCodeBlock() {
        let text = "a\n*      x"

        let expectedDump = """
        Document @1:1-2:9
        ├─ Paragraph @1:1-1:2
        │  └─ Text @1:1-1:2 "a"
        └─ UnorderedList @2:1-2:9
           └─ ListItem @2:1-2:9
              └─ CodeBlock @2:7-2:9 language: none
                  x
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// With no paragraph open, an empty marker with trailing whitespace still opens an empty list -
    /// the no-interrupt rule is scoped to paragraph continuation only.
    func testStandaloneEmptyItemFormsList() {
        let text = "*  "

        let expectedDump = """
        Document @1:1-1:4
        └─ UnorderedList @1:1-1:4
           └─ ListItem @1:1-1:4
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
