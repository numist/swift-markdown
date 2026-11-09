/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest
import Testing

/// Strong emphasis around an interior `**` that can both open and close.
///
/// Rule 10 of Emphasis and strong emphasis sums the lengths of whole delimiter runs, and the `openers_bottom`
/// table (An algorithm for parsing nested emphasis and links) is keyed by the closing run's length modulo 3;
/// both use a run's full length, not what remains of it after earlier matches.
class EmphasisNestingTests: XCTestCase {
    /// `(4 + 2) % 3 == 0`, so the interior `**` matches neither outer run and is text. The outer runs match
    /// twice, as two nested strong emphasis spans.
    func testDoubleRunNestsAroundUnpairableInterior() {
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

/// A `~` is a punctuation character (Characters and lines), so a delimiter run beside a `~` run is classified
/// against the `~`, not against the character past it.
@Suite struct StrikethroughFlankingEmphasisTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func closerAfterPunctuationBeforeTilde() {
        #expect(tree("*-*~a") == """
            Document @1:1-1:6
            └─ Paragraph @1:1-1:6
               ├─ Emphasis @1:1-1:4
               │  └─ Text @1:2-1:3 "-"
               └─ Text @1:4-1:6 "~a"
            """)
        #expect(tree("*.*~~a") == """
            Document @1:1-1:7
            └─ Paragraph @1:1-1:7
               ├─ Emphasis @1:1-1:4
               │  └─ Text @1:2-1:3 "."
               └─ Text @1:4-1:7 "~~a"
            """)
    }

    @Test func openerAfterTildeBeforePunctuation() {
        #expect(tree("a~*-x*") == """
            Document @1:1-1:7
            └─ Paragraph @1:1-1:7
               ├─ Text @1:1-1:3 "a~"
               └─ Emphasis @1:3-1:7
                  └─ Text @1:4-1:6 "-x"
            """)
    }
}
