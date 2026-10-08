/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A code span or raw HTML that contains a line ending has a source range that ends on the line of its
/// closing delimiter. `.disableSourcePosOpts` does not affect source ranges.
class CrossLineCodeSpanAndRawHTMLRangeTests: XCTestCase {
    func testMultilineCodeSpanEndsOnPhysicalLine() {
        let text = "`a\nb`"

        let expectedDump = """
        Document @1:1-2:3
        └─ Paragraph @1:1-2:3
           └─ InlineCode @1:1-2:3 `a b`
        """

        let document = Document(parsing: text, options: [.disableSourcePosOpts])
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testMultilineInlineHTMLEndsOnPhysicalLine() {
        let text = "<foo\nbar>"

        let expectedDump = """
        Document @1:1-2:5
        └─ Paragraph @1:1-2:5
           └─ InlineHTML @1:1-2:5 <foo
        bar>
        """

        let document = Document(parsing: text, options: [.disableSourcePosOpts])
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testMultilineCodeSpanEndsOnPhysicalLineWithoutOptions() {
        let text = "`a\nb`"

        let expectedDump = """
        Document @1:1-2:3
        └─ Paragraph @1:1-2:3
           └─ InlineCode @1:1-2:3 `a b`
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testTextAfterMultilineCodeSpanKeepsPhysicalLine() {
        let text = "`\n`8"

        let expectedDump = """
        Document @1:1-2:3
        └─ Paragraph @1:1-2:3
           ├─ InlineCode @1:1-2:2 ` `
           └─ Text @2:2-2:3 "8"
        """

        let document = Document(parsing: text, options: [.disableSourcePosOpts])
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
