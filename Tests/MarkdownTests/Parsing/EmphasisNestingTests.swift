/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// How runs of `*` pair into emphasis and strong emphasis, and how the matches nest.
///
/// Rule 10 of Emphasis and strong emphasis sums the lengths of whole delimiter runs, and the `openers_bottom`
/// table (An algorithm for parsing nested emphasis and links) is keyed by the closing run's length modulo 3 and,
/// so that it skips no opener rule 9 admits, by whether the closer can also open. Both use a run's full length,
/// not what remains of it after earlier matches.
class EmphasisNestingTests: XCTestCase {
    /// The `****` closes the `***` as strong emphasis, which leaves one `*` of the opener and two of the closer.
    /// Rule 9 sums the runs' lengths, 3 and 4, not the 1 and 2 delimiters left, so those match again as emphasis, and
    /// the closer's last `*` is text.
    func testSecondMatchSumsWholeRunLengths() {
        let text = "***a****a"

        let expectedDump = """
        Document @1:1-1:10
        └─ Paragraph @1:1-1:10
           ├─ Emphasis @1:1-1:8
           │  └─ Strong @1:2-1:7
           │     └─ Text @1:4-1:5 "a"
           └─ Text @1:8-1:10 "*a"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// The interior `**` can both open and close and `(4 + 2) % 3 == 0`, so it matches neither outer run and is
    /// text. The outer runs match twice, as two nested strong emphasis spans.
    func testInteriorDoubleRunStaysTextInsideNestedStrong() {
        let text = "****a**o****"

        let expectedDump = """
        Document @1:1-1:13
        └─ Paragraph @1:1-1:13
           └─ Strong @1:1-1:13
              └─ Strong @1:3-1:11
                 └─ Text @1:5-1:9 "a**o"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// The closing `**` matches the interior `**`, so the opening `****` is text.
    func testShortCloserLeavesOpenerLiteral() {
        let text = "****a**o**"

        let expectedDump = """
        Document @1:1-1:11
        └─ Paragraph @1:1-1:11
           ├─ Text @1:1-1:6 "****a"
           └─ Strong @1:6-1:11
              └─ Text @1:8-1:9 "o"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testDoubleRunWithoutInteriorNests() {
        let text = "****o****"

        let expectedDump = """
        Document @1:1-1:10
        └─ Paragraph @1:1-1:10
           └─ Strong @1:1-1:10
              └─ Strong @1:3-1:8
                 └─ Text @1:5-1:6 "o"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// `(2 + 6) % 3 != 0`, so the interior `**` matches the closing run around `foo`; the rest of the
    /// closing run then matches the opening run twice.
    func testInteriorPairsWithMultipleOfThreeCloser() {
        let text = "****a**foo******"

        let expectedDump = """
        Document @1:1-1:17
        └─ Paragraph @1:1-1:17
           └─ Strong @1:1-1:17
              └─ Strong @1:3-1:15
                 ├─ Text @1:5-1:6 "a"
                 └─ Strong @1:6-1:13
                    └─ Text @1:8-1:11 "foo"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// The last `*` can't open, so rule 9's multiple-of-3 test, which kept the interior `*` from matching the `**`,
    /// doesn't apply to it, and it matches the `**`.
    func testCloserThatCannotOpenMatchesOpenerSkippedByOneThatCan() {
        let text = "**a*a*a*"

        let expectedDump = """
        Document @1:1-1:9
        └─ Paragraph @1:1-1:9
           ├─ Text @1:1-1:2 "*"
           └─ Emphasis @1:2-1:9
              ├─ Text @1:3-1:4 "a"
              ├─ Emphasis @1:4-1:7
              │  └─ Text @1:5-1:6 "a"
              └─ Text @1:7-1:8 "a"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
