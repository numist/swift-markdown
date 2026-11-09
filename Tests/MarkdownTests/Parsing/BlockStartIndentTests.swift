/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// An ATX heading, thematic break or HTML block start may be indented by up to three spaces; a line indented
/// by four or more columns is an indented code block. A tab advances to the next tab stop of 4 columns (Tabs),
/// so a tab-indented line after a block quote's fenced code block is indented code.
class BlockStartIndentTests: XCTestCase {
    // MARK: ATX heading

    func testThreeSpaceIndentedATXOpensHeading() {
        let expectedDump = """
        Document @1:1-1:7
        └─ Heading @1:4-1:7 level: 1
           └─ Text @1:6-1:7 "x"
        """
        XCTAssertEqual(expectedDump, Document(parsing: "   # x").debugDescription(options: .printSourceLocations))
    }

    func testTabIndentedATXBecomesIndentedCode() {
        let expectedDump = """
        Document @1:1-2:5
        ├─ BlockQuote @1:1-1:5
        │  └─ CodeBlock @1:2-1:5 language: none

        └─ CodeBlock @2:2-2:5 language: none
           # x
        """
        XCTAssertEqual(expectedDump, Document(parsing: ">~~~\n\t# x").debugDescription(options: .printSourceLocations))
    }

    // MARK: Thematic break

    func testThreeSpaceIndentedThematicBreakOpens() {
        let expectedDump = """
        Document @1:1-1:7
        └─ ThematicBreak @1:4-1:7
        """
        XCTAssertEqual(expectedDump, Document(parsing: "   ***").debugDescription(options: .printSourceLocations))
    }

    func testTabIndentedThematicBreakBecomesIndentedCode() {
        let expectedDump = """
        Document @1:1-2:5
        ├─ BlockQuote @1:1-1:5
        │  └─ CodeBlock @1:2-1:5 language: none

        └─ CodeBlock @2:2-2:5 language: none
           ***
        """
        XCTAssertEqual(expectedDump, Document(parsing: ">~~~\n\t***").debugDescription(options: .printSourceLocations))
    }

    // MARK: HTML block

    func testThreeSpaceIndentedHTMLBlockOpens() {
        let expectedDump = """
        Document @1:1-1:9
        └─ HTMLBlock @1:1-1:9
              <pre>
        """
        XCTAssertEqual(expectedDump, Document(parsing: "   <pre>").debugDescription(options: .printSourceLocations))
    }

    func testTabIndentedHTMLBlockBecomesIndentedCode() {
        let expectedDump = """
        Document @1:1-2:7
        ├─ BlockQuote @1:1-1:5
        │  └─ CodeBlock @1:2-1:5 language: none

        └─ CodeBlock @2:2-2:7 language: none
           <pre>
        """
        XCTAssertEqual(expectedDump, Document(parsing: ">~~~\n\t<pre>").debugDescription(options: .printSourceLocations))
    }
}
