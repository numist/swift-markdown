/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Source ranges for a link/image/attribute whose `(...)` destination/title crosses a newline.
///
/// The shipped (flag-off, spec-correct) parser stamps such a node's end at the *byte-projected*
/// position of just past its closing `)` - i.e. on the `)`'s own physical line. cmark-gfm's flat
/// end column, which keeps counting from the `]`'s line without resetting at the interior newline
/// (`[a](\n/u)` -> `Link @1:1-1:9`), is the `.cmarkBugCompatibility` quirk, covered by the
/// `s518-multiline-*` fuzzer regression pairs (which parse flag-on). This suite is the flag-off
/// guardrail proving the default parser is spec-correct: the node ends on the `)`'s physical line.
///
/// Single-line links and newline-in-*text* links never take the quirk path (their `(...)` has no
/// interior newline), so they are asserted here to be identical in both flag states, complementing
/// `CommonMarkConverterTests.testMulitlineLinks`.
class MultilineLinkEndColumnTests: XCTestCase {
    /// A multi-line link's destination on the next line ends just past the `)` on that physical
    /// line (byte-projected @2:4), not at cmark's flat @1:9.
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

    /// A multi-line link whose title is on the next line ends on that physical line (byte-projected
    /// @2:11 - short of the `)` because the trailing spaces before `)` fall outside the link node's
    /// byte range), not at cmark's flat @1:26.
    func testMultilineLinkTitleEndsOnPhysicalLine() {
        let text = "[link](   /uri\n  \"title\"  )"

        let expectedDump = """
        Document @1:1-2:13
        └─ Paragraph @1:1-2:13
           └─ Link @1:1-2:11 destination: "/uri"
              └─ Text @1:2-1:6 "link"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// A multi-line image whose title is on the next line ends just past the `)` on that physical
    /// line (byte-projected @2:5), not at cmark's flat @1:13.
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

    /// Control: a single-line link never crosses a newline in `(...)`, so it is byte-projected in
    /// both flag states.
    func testSingleLineLinkUnchanged() {
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

    /// Control: a newline in the link *text* precedes the `]`, so `(...)` has no interior newline
    /// and the node is byte-projected in both flag states (the `testMulitlineLinks` shape).
    func testNewlineInTextLinkUnchanged() {
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
