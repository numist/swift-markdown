/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A paragraph made only of link reference definitions, followed by a setext heading underline and then
/// content. Once the definitions are removed there is no content to underline, so no setext heading forms
/// (Setext headings): `===` cannot interrupt a paragraph and is its text, while `---` is a thematic break,
/// which can. Each block starts at its first content byte.
class RefDefSetextStructureTests: XCTestCase {
    func testEqualsUnderlineAfterRefDefIsParagraphText() {
        let text = "[a]: /u\n===\nx"

        let expectedDump = """
        Document @1:1-3:2
        └─ Paragraph @2:1-3:2
           ├─ Text @2:1-2:4 "==="
           ├─ SoftBreak
           └─ Text @3:1-3:2 "x"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// The removed link reference definition is defined, so a later `[foo]` resolves against it.
    func testRefDefBeforeEqualsUnderlineIsDefined() {
        let text = "[foo]: /url\n===\n[foo]"

        let expectedDump = """
        Document @1:1-3:6
        └─ Paragraph @2:1-3:6
           ├─ Text @2:1-2:4 "==="
           ├─ SoftBreak
           └─ Link @3:1-3:6 destination: "/url"
              └─ Text @3:2-3:5 "foo"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testDashUnderlineAfterRefDefBecomesThematicBreak() {
        let text = "[a]: /u\n---\nx"

        let expectedDump = """
        Document @1:1-3:2
        ├─ ThematicBreak @2:1-2:4
        └─ Paragraph @3:1-3:2
           └─ Text @3:1-3:2 "x"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Content before the underline forms a setext heading, and the link reference definition after it is
    /// removed from the next paragraph.
    func testContentBeforeUnderlineIsSetextHeading() {
        let text = "z\n===\n[a]: /u\nx"

        let expectedDump = """
        Document @1:1-4:2
        ├─ Heading @1:1-2:4 level: 1
        │  └─ Text @1:1-1:2 "z"
        └─ Paragraph @4:1-4:2
           └─ Text @4:1-4:2 "x"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
