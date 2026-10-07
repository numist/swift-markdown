/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
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
}

/// A `*` or `_` delimiter run directly followed by a `~` run that is itself followed by a letter is
/// classified as left- or right-flanking as though the letter followed it. After punctuation, such a run is
/// left-flanking only and cannot close emphasis.
@Suite struct StrikethroughFlankingEmphasisTests {
    private func formsEmphasis(_ markdown: String) -> Bool {
        Document(parsing: markdown).debugDescription(options: []).contains("Emphasis")
    }

    @Test func canOpenTildeAfterPunctuationCloserBlocksEmphasis() throws {
        // Without these, the expectations below would hold if emphasis never formed at all.
        try #require(formsEmphasis("*x*~a"), "letter-content closer stays right-flanking; must form emphasis")
        try #require(formsEmphasis("*-*"), "isolated *-* must form emphasis (closer's after-char is the line end)")
        try #require(formsEmphasis("*-*~"), "bare trailing ~ (can-close, not can-open) must form emphasis")

        #expect(!formsEmphasis("*-*~a"))
        #expect(!formsEmphasis("*.*~a"))
    }
}

