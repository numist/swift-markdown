/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Where whitespace defines block structure, a tab behaves as if replaced by spaces with a tab stop of
/// 4 characters; elsewhere it is not expanded (Tabs). Inline content after a tab that follows a container
/// marker keeps its source positions, and a tab inside paragraph text stays literal. Columns count a tab as
/// one byte.
class MaterializedEmphasisSourcePositionTests: XCTestCase {
    func testBulletTabEmphasis() {
        let text = "*\t*5*"

        let expectedDump = """
        Document @1:1-1:6
        └─ UnorderedList @1:1-1:6
           └─ ListItem @1:1-1:6
              └─ Paragraph @1:3-1:6
                 └─ Emphasis @1:3-1:6
                    └─ Text @1:4-1:5 "5"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testBlockQuoteTabEmphasis() {
        let text = ">\t*5*"

        let expectedDump = """
        Document @1:1-1:6
        └─ BlockQuote @1:1-1:6
           └─ Paragraph @1:3-1:6
              └─ Emphasis @1:3-1:6
                 └─ Text @1:4-1:5 "5"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testTabOneColumnBeforeTabStopStaysLiteral() {
        let text = "***\tx"

        let expectedDump = """
        Document @1:1-1:6
        └─ Paragraph @1:1-1:6
           └─ Text @1:1-1:6 "***\tx"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testInteriorTabParagraph() {
        let text = "**\tx"

        let expectedDump = """
        Document @1:1-1:5
        └─ Paragraph @1:1-1:5
           └─ Text @1:1-1:5 "**\tx"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
