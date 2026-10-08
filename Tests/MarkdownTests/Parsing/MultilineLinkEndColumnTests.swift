/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A link or image whose destination or title is on a later line has a source range that ends just past
/// its closing `)` on that line.
class MultilineLinkEndColumnTests: XCTestCase {
    func testMultilineLinkDestinationEndsOnPhysicalLine() {
        let text = "[a](\n/u)"

        let expectedDump = """
        Document @1:1-2:4
        └─ Paragraph @1:1-2:4
           └─ Link @1:1-2:4 destination: "/u"
              └─ Text @1:2-1:3 "a"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testMultilineLinkTitleEndsOnPhysicalLine() {
        let text = "[link](   /uri\n  \"title\"  )"

        let expectedDump = """
        Document @1:1-2:13
        └─ Paragraph @1:1-2:13
           └─ Link @1:1-2:13 destination: "/uri"
              └─ Text @1:2-1:6 "link"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testMultilineImageEndsOnPhysicalLine() {
        let text = "![x](/u\n\"t\")"

        let expectedDump = """
        Document @1:1-2:5
        └─ Paragraph @1:1-2:5
           └─ Image @1:1-2:5 source: "/u" title: "t"
              └─ Text @1:3-1:4 "x"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testSingleLineLinkEndsPastClosingParenthesis() {
        let text = "[a](/b)"

        let expectedDump = """
        Document @1:1-1:8
        └─ Paragraph @1:1-1:8
           └─ Link @1:1-1:8 destination: "/b"
              └─ Text @1:2-1:3 "a"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testLinkWithLineEndingInTextEndsOnClosingLine() {
        let text = "[a\nb](/u)"

        let expectedDump = """
        Document @1:1-2:7
        └─ Paragraph @1:1-2:7
           └─ Link @1:1-2:7 destination: "/u"
              ├─ Text @1:2-1:3 "a"
              ├─ SoftBreak
              └─ Text @2:1-2:2 "b"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
