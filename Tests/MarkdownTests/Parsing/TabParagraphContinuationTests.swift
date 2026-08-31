/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A paragraph continuation line that begins with a tab.
///
/// A leading tab makes the parser materialize a tab-expanded per-line buffer for the line, so the
/// continuation's surviving content is not read straight from the source span. The content past the
/// expanded prefix is nonetheless byte-identical to source (`expandPrefixTabs` copies the tail
/// verbatim), so it must resolve to the literal source bytes - a single soft break joins the lines
/// and the text survives, exactly like a space-indented continuation. Columns are byte-projected
/// (a tab counts as one byte) in the shipped, flag-off parser.
class TabParagraphContinuationTests: XCTestCase {
    /// A one-tab continuation: `bar` survives with a single soft break; its column is byte-projected
    /// just past the one-byte tab (@2:2).
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

    /// Two tab-led continuation lines: each contributes exactly one soft break and keeps its text.
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

    /// Two leading tabs are both stripped as indentation; the text still survives with one soft break,
    /// its column byte-projected past the two one-byte tabs (@2:3).
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
