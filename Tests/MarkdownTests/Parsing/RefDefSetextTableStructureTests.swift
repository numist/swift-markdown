/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A paragraph made only of link reference definitions, followed by a setext heading underline. Once the
/// definitions are removed, the underline is the first line of a paragraph or the header row of a table
/// (Tables (extension)).
class RefDefSetextTableStructureTests: XCTestCase {
    func testUnderlineIsTableHeaderRow() {
        let text = "[r]:o\n=\n|-"

        let expectedDump = """
        Document @1:1-3:3
        └─ Table @2:1-3:3 alignments: |-|
           ├─ Head @2:1-2:2
           │  └─ Cell @2:1-2:2
           │     └─ Text @2:1-2:2 "="
           └─ Body
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testParagraphStartsAfterDefinition() {
        let text = "[r]:o\n=\nx"

        let expectedDump = """
        Document @1:1-3:2
        └─ Paragraph @2:1-3:2
           ├─ Text @2:1-2:2 "="
           ├─ SoftBreak
           └─ Text @3:1-3:2 "x"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testTableAfterMultilineDefinitionStartsAtHeaderRow() {
        let text = "[f]:\n \"\n=\n|-"

        let expectedDump = """
        Document @1:1-4:3
        └─ Table @3:1-4:3 alignments: |-|
           ├─ Head @3:1-3:2
           │  └─ Cell @3:1-3:2
           │     └─ Text @3:1-3:2 "="
           └─ Body
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testUnderlineIsTableHeaderRowInBlockQuote() {
        let text = "> [r]:o\n> =\n> |-"

        let expectedDump = """
        Document @1:1-3:5
        └─ BlockQuote @1:1-3:5
           └─ Table @2:3-3:5 alignments: |-|
              ├─ Head @2:3-2:4
              │  └─ Cell @2:3-2:4
              │     └─ Text @2:3-2:4 "="
              └─ Body
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testUnderlineIsParagraphBeforeTable() {
        let text = "[r]:o\n=\nfoo\n|-"

        let expectedDump = """
        Document @1:1-4:3
        ├─ Paragraph @2:1-2:2
        │  └─ Text @2:1-2:2 "="
        └─ Table @3:1-4:3 alignments: |-|
           ├─ Head @3:1-3:4
           │  └─ Cell @3:1-3:4
           │     └─ Text @3:1-3:4 "foo"
           └─ Body
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
