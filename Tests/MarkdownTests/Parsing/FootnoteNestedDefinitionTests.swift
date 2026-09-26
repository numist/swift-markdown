/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(Footnotes) @testable import Markdown
import XCTest

/// A footnote definition opener followed on the same line by another opener nests the second
/// definition inside the first. cmark-gfm's `process_footnotes` (blocks.c) registers definitions on
/// the tree walk's EXIT events, so an inner definition registers before the one enclosing it, and
/// the first-registered definition of a label wins (`sort_map`, map.c). A referenced definition moves
/// to the document root out of whatever encloses it; every other definition is dropped with its
/// remaining content.
class FootnoteNestedDefinitionTests: XCTestCase {
    /// Asserts `markdown`'s surface both with and without `.cmarkBugCompatibility`: cmark's
    /// winner choice is the only defined behavior for nested definitions, so it holds flag-OFF too.
    private func assertSurface(_ expected: String, _ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        for options: ParseOptions in [[.footnotes, .cmarkBugCompatibility], [.footnotes]] {
            XCTAssertEqual(expected, Document(parsing: markdown, options: options).debugDescription(options: []), "options: \(options)", file: file, line: line)
        }
    }

    func testInnerDuplicateDefinitionWins() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "b" index: 1
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  └─ Text "A"
            """,
            "[^b]\n[^b]:[^b]:A")
    }

    /// The winning definition supplies the reference's displayed label.
    func testInnerDuplicateDefinitionSuppliesLabel() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "B" index: 1
            └─ FootnoteDefinition label: "B"
               └─ Paragraph
                  └─ Text "A"
            """,
            "[^b]\n[^b]:[^B]:A")
    }

    func testThreeLevelDuplicateInnermostWins() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "b" index: 1
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  └─ Text "A"
            """,
            "[^b]\n[^b]:[^b]:[^b]:A")
    }

    /// A differently labeled inner definition moves out of the outer one when referenced.
    func testDifferentInnerLabelBothReferenced() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  ├─ FootnoteReference label: "a" index: 1
            │  └─ FootnoteReference label: "b" index: 2
            ├─ FootnoteDefinition label: "a"
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  └─ Text "A"
            """,
            "[^a][^b]\n[^a]:[^b]:A")
    }

    /// An unreferenced inner definition is dropped from inside the referenced outer one.
    func testDifferentInnerLabelOnlyOuterReferenced() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "a" index: 1
            └─ FootnoteDefinition label: "a"
            """,
            "[^a]\n[^a]:[^b]:A")
    }

    /// The indented line continues only the outer definition, so its paragraph is lost with the
    /// losing outer duplicate.
    func testOuterDuplicateContentAfterNewlineIsDropped() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "b" index: 1
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  └─ Text "A"
            """,
            "[^b]\n[^b]:[^b]:A\n\n    C\n")
    }

    /// A lazy continuation line extends the inner definition's paragraph.
    func testInnerDuplicateLazyContinuation() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "b" index: 1
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  ├─ Text "A"
                  ├─ SoftBreak
                  └─ Text "B"
            """,
            "[^b]\n[^b]:[^b]:A\nB\n")
    }

    func testInnerDuplicateInsideListItem() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "b" index: 1
            ├─ UnorderedList
            │  └─ ListItem
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  └─ Text "A"
            """,
            "[^b]\n- [^b]:[^b]:A\n")
    }

    /// A same-label definition nested through a block quote still closes first and wins; the losing
    /// outer definition is dropped with its emptied block quote.
    func testInnerDuplicateThroughBlockQuote() {
        assertSurface(
            """
            Document
            ├─ Paragraph
            │  └─ FootnoteReference label: "b" index: 1
            └─ FootnoteDefinition label: "b"
               └─ Paragraph
                  └─ Text "A"
            """,
            "[^b]\n[^b]:> [^b]:A\n")
    }
}
