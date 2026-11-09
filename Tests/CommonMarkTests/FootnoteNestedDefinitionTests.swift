/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote definition opener followed on the same line by another opener nests the second
/// definition inside the first. The first definition of a label in the document wins, so an enclosing
/// definition wins over a same-label one nested in it. A referenced definition moves to the document root
/// out of whatever encloses it; every other definition is dropped with its remaining content.
@Suite("Nested footnote definitions")
struct FootnoteNestedDefinitionTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    /// The winning definition supplies the reference's displayed label.
    @Test
    func testOuterDuplicateDefinitionSuppliesLabel() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^B]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"

            """)
    }

    @Test
    func testThreeLevelDuplicateOutermostWins() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^b]:[^b]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"

            """)
    }

    /// A differently labeled inner definition moves out of the outer one when referenced.
    @Test
    func testDifferentInnerLabelBothReferenced() {
        #expect(TreeDump.dump("[^a][^b]\n[^a]:[^b]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
                footnote_reference "2"
              footnote_definition "a"
              footnote_definition "b"
                paragraph
                  text "A"

            """)
    }

    /// An unreferenced inner definition is dropped from inside the referenced outer one.
    @Test
    func testDifferentInnerLabelOnlyOuterReferenced() {
        #expect(TreeDump.dump("[^a]\n[^a]:[^b]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"

            """)
    }

    /// The indented line continues only the outer definition, so its paragraph stays with the
    /// winning outer duplicate.
    @Test
    func testOuterDuplicateKeepsContentAfterBlankLine() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^b]:A\n\n    C\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                paragraph
                  text "C"

            """)
    }

    /// A lazy continuation line extends the inner definition's paragraph, which is dropped with
    /// the losing inner duplicate.
    @Test
    func testInnerDuplicateLazyContinuationIsDropped() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^b]:A\nB\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"

            """)
    }

    @Test
    func testOuterDuplicateInsideListItem() {
        #expect(TreeDump.dump("[^b]\n- [^b]:[^b]:A\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              list bullet '-' tight
                item
              footnote_definition "b"

            """)
    }

    /// A same-label definition nested through a block quote loses to the outer definition, which
    /// keeps the emptied block quote.
    @Test
    func testOuterDuplicateThroughBlockQuote() {
        #expect(TreeDump.dump("[^b]\n[^b]:> [^b]:A\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                block_quote

            """)
    }
}
