/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Block structure when a reference-definition-only paragraph is immediately followed by a
/// setext-underline (`===`/`---`) line and then content.
///
/// The shipped (flag-off, spec-correct) parser strips the leading reference definitions, finds the
/// paragraph empty, drops it, and redispatches the underline line as a *fresh* block: `===` (not a
/// thematic break) opens a new paragraph on its own physical line, while `---` becomes a thematic
/// break. Content that follows keeps its true source positions.
///
/// cmark-gfm instead keeps the ref-def-only paragraph open across the underline (draining the defs
/// but neither promoting to a heading nor breaking), so the underline becomes paragraph text stamped
/// from the paragraph's original start line. That divergent structure is the `.cmarkBugCompatibility`
/// quirk, covered flag-on by the `refsetext-*` fuzzer regression pairs. This suite is the flag-off
/// guardrail proving the default parser produces the spec-correct fresh-block structure.
class RefDefSetextStructureTests: XCTestCase {
    /// `===` after a ref-def-only line is not a thematic break, so it opens a fresh paragraph on
    /// line 2; the following content keeps its true positions.
    func testEqualsUnderlineAfterRefDefOpensFreshParagraph() {
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

    /// The dropped reference definition is still registered, so a later `[foo]` shortcut in the
    /// fresh paragraph resolves against it.
    func testEqualsUnderlineAfterRefDefStillRegistersDefinition() {
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

    /// `---` after a ref-def-only line becomes a thematic break, and the following content opens a
    /// fresh paragraph on line 3.
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

    /// Control: real content before the underline promotes to a setext heading, and the trailing
    /// ref-def is handled normally - so the empty-paragraph *structure* divergence is specific to a
    /// ref-def-*only* paragraph preceding the underline. (The block structure here matches flag-on;
    /// only the trailing paragraph's inline `x` position differs, shifted up one line flag-on by the
    /// finalize-time ref-def line-shift - see the `refsetext-realheading-ctl` fuzzer pair.)
    func testRealContentBeforeUnderlineIsSetextHeading() {
        let text = "z\n===\n[a]: /u\nx"

        let expectedDump = """
        Document @1:1-4:2
        ├─ Heading @1:1-3:8 level: 1
        │  └─ Text @1:1-1:2 "z"
        └─ Paragraph @3:1-4:2
           └─ Text @4:1-4:2 "x"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
