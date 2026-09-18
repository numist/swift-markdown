/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Block structure when a reference-definition-only paragraph is followed by a setext-underline line
/// under `.cmarkBugCompatibility` (flag-on, matching cmark-gfm's quirks).
///
/// cmark keeps the ref-def-only paragraph open across the underline, draining the definitions and
/// absorbing the underline as paragraph text (`resolve_reference_link_definitions` drops the defs from
/// the buffer but neither promotes to a heading nor breaks). The rewrite reproduces that by RESTORING
/// the resolved definitions into the buffer so a later paragraph finalize re-extracts them.
///
/// That reconstruction must NOT fire when the underline line is really a GFM table header: cmark opens
/// the table over the (already ref-def-drained) buffer, so the definitions are gone and no preceding
/// paragraph forms. This suite guards both sides of that boundary.
class RefDefSetextTableStructureTests: XCTestCase {
    private static let flagOn: ParseOptions = [.cmarkBugCompatibility]

    /// A ref-def, a setext-shaped `=` line, then a table delimiter row: cmark forms a table only (the
    /// `=` is its header, `|-` the delimiter), consuming the ref-def silently. The reconstruction must
    /// be suppressed so the resolved `[r]:o` does not leak back as a spurious preceding paragraph.
    func testReconstructionSuppressedWhenLinesFormTable() {
        let text = "[r]:o\n=\n|-"

        let expectedDump = """
        Document @1:1-3:3
        └─ Table @2:1-3:3 alignments: |-|
           ├─ Head @2:1-2:2
           │  └─ Cell @2:1-2:2
           │     └─ Text @2:1-2:2 "="
           └─ Body
        """

        let document = Document(parsing: text, options: Self.flagOn)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Control differing only in the third line: a plain continuation (not a delimiter row) leaves the
    /// reconstruction intact - the ref-def is dropped, the `=` and `x` remain as one paragraph, and no
    /// link forms from the consumed `[r]` definition.
    func testReconstructionStillFiresWhenNoTableForms() {
        let text = "[r]:o\n=\nx"

        let expectedDump = """
        Document @1:1-3:2
        └─ Paragraph @1:1-3:2
           ├─ Text @2:1-2:2 "="
           ├─ SoftBreak
           └─ Text @3:1-3:2 "x"
        """

        let document = Document(parsing: text, options: Self.flagOn)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// A multi-line ref-def whose reconstructed buffer is arena-materialized (not a contiguous source
    /// range): the same suppression must apply, so the table forms alone and the definitions do not leak.
    func testMaterializedReconstructionSuppressedWhenLinesFormTable() {
        let text = "[f]:\n \"\n=\n|-"

        let expectedDump = """
        Document @1:1-4:3
        └─ Table @1:1-4:3 alignments: |-|
           ├─ Head
           │  └─ Cell
           │     └─ Text "="
           └─ Body
        """

        let document = Document(parsing: text, options: Self.flagOn)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// A block-quote-nested ref-def whose reconstructed buffer is a segment list (the underline line's
    /// stripped `>` prefix breaks source contiguity): suppression applies there too - a table inside the
    /// quote, no spurious paragraph.
    func testSegmentedReconstructionSuppressedWhenLinesFormTable() {
        let text = "> [r]:o\n> =\n> |-"

        let expectedDump = """
        Document @1:1-3:5
        └─ BlockQuote @1:1-3:5
           └─ Table @2:3-3:5 alignments: |-|
              ├─ Head
              │  └─ Cell
              │     └─ Text "="
              └─ Body
        """

        let document = Document(parsing: text, options: Self.flagOn)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// When absorbed text follows the underline before the delimiter row, only the LEADING ref-defs are
    /// dropped: `foo` becomes the header, the absorbed `=` becomes the preceding paragraph, and `[r]:o`
    /// (a leading def) is gone - matching cmark's drained buffer.
    func testReconstructionDropsOnlyLeadingRefDefsBeforeTable() {
        let text = "[r]:o\n=\nfoo\n|-"

        let expectedDump = """
        Document @1:1-4:3
        ├─ Paragraph @2:1-2:2
        │  └─ Text @2:1-2:2 "="
        └─ Table @3:1-4:3 alignments: |-|
           ├─ Head @3:1-3:4
           │  └─ Cell @3:1-3:4
           │     └─ Text @3:1-3:4 "foo"
           └─ Body
        """

        let document = Document(parsing: text, options: Self.flagOn)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
