/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A paragraph continuation line that begins with tabs loses them as initial whitespace (Paragraphs), and its
/// text follows a single soft line break. Columns count a tab as one byte.
class TabParagraphContinuationTests: XCTestCase {
    func testSingleTabContinuation() {
        let text = "foo\n\tbar"

        let expectedDump = """
        Document @1:1-2:5
        └─ Paragraph @1:1-2:5
           ├─ Text @1:1-1:4 "foo"
           ├─ SoftBreak
           └─ Text @2:2-2:5 "bar"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testMultipleTabContinuationLines() {
        let text = "foo\n\tbar\n\tbaz"

        let expectedDump = """
        Document @1:1-3:5
        └─ Paragraph @1:1-3:5
           ├─ Text @1:1-1:4 "foo"
           ├─ SoftBreak
           ├─ Text @2:2-2:5 "bar"
           ├─ SoftBreak
           └─ Text @3:2-3:5 "baz"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testTwoLeadingTabsContinuation() {
        let text = "foo\n\t\tbar"

        let expectedDump = """
        Document @1:1-2:6
        └─ Paragraph @1:1-2:6
           ├─ Text @1:1-1:4 "foo"
           ├─ SoftBreak
           └─ Text @2:3-2:6 "bar"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
