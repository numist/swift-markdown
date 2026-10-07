/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// An empty list item cannot interrupt a paragraph (List items). A list marker followed only by
/// whitespace opens an empty item, however much whitespace follows it.
class EmptyListItemInterruptTests: XCTestCase {
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

    /// Six spaces after the marker, enough to start indented code, leave the item empty when no content
    /// follows them.
    func testManyTrailingSpacesLeaveItemEmptyAndDoNotInterruptParagraph() {
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

    /// Five or more spaces before content start the item with an indented code block (List items), so
    /// the item is not empty.
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
