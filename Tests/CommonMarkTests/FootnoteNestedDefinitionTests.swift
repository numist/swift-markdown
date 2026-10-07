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
/// definition inside the first. cmark-gfm's `process_footnotes` (blocks.c) registers definitions on
/// the tree walk's EXIT events, so an inner definition registers before the one enclosing it, and
/// the first-registered definition of a label wins (`sort_map`, map.c). A referenced definition moves
/// to the document root out of whatever encloses it; every other definition is dropped with its
/// remaining content.
@Suite("Nested footnote definitions")
struct FootnoteNestedDefinitionTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    /// The winning definition supplies the reference's displayed label.
    @Test
    func testInnerDuplicateDefinitionSuppliesLabel() {
        #expect(CmarkTreeDump.dump("[^b]\n[^b]:[^B]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "B"
                paragraph
                  text "A"

            """)
    }

    @Test
    func testThreeLevelDuplicateInnermostWins() {
        #expect(CmarkTreeDump.dump("[^b]\n[^b]:[^b]:[^b]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                paragraph
                  text "A"

            """)
    }

    /// A differently labeled inner definition moves out of the outer one when referenced.
    @Test
    func testDifferentInnerLabelBothReferenced() {
        #expect(CmarkTreeDump.dump("[^a][^b]\n[^a]:[^b]:A", options: Self.options) == """
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
        #expect(CmarkTreeDump.dump("[^a]\n[^a]:[^b]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"

            """)
    }

    /// The indented line continues only the outer definition, so its paragraph is lost with the
    /// losing outer duplicate.
    @Test
    func testOuterDuplicateContentAfterNewlineIsDropped() {
        #expect(CmarkTreeDump.dump("[^b]\n[^b]:[^b]:A\n\n    C\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                paragraph
                  text "A"

            """)
    }

    /// A lazy continuation line extends the inner definition's paragraph.
    @Test
    func testInnerDuplicateLazyContinuation() {
        #expect(CmarkTreeDump.dump("[^b]\n[^b]:[^b]:A\nB\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                paragraph
                  text "A"
                  softbreak
                  text "B"

            """)
    }

    @Test
    func testInnerDuplicateInsideListItem() {
        #expect(CmarkTreeDump.dump("[^b]\n- [^b]:[^b]:A\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              list bullet '-' tight
                item
              footnote_definition "b"
                paragraph
                  text "A"

            """)
    }

    /// A same-label definition nested through a block quote still closes first and wins; the losing
    /// outer definition is dropped with its emptied block quote.
    @Test
    func testInnerDuplicateThroughBlockQuote() {
        #expect(CmarkTreeDump.dump("[^b]\n[^b]:> [^b]:A\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                paragraph
                  text "A"

            """)
    }
}
