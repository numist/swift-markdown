/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// An opener after another on the same line nests a definition in the first. The first definition of a label wins;
// a winning, referenced definition moves to the document root, and every other is dropped with its remaining content.
@Suite("Nested footnote definitions")
struct FootnoteNestedDefinitionTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    @Test
    func outerDuplicateDefinitionSuppliesLabel() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^B]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"

            """)
    }

    @Test
    func threeLevelDuplicateOutermostWins() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^B]:[^b]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"

            """)
    }

    @Test
    func differentInnerLabelBothReferenced() {
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

    @Test
    func differentInnerLabelOnlyOuterReferenced() {
        #expect(TreeDump.dump("[^a]\n[^a]:[^b]:A", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"

            """)
    }

    // Four columns of indentation continue only the outer definition, so `C` stays with the winning outer duplicate.
    @Test
    func outerDuplicateKeepsContentAfterBlankLine() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^b]:A\n\n    C\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                paragraph
                  text "C"

            """)
    }

    @Test
    func innerDuplicateLazyContinuationIsDropped() {
        #expect(TreeDump.dump("[^b]\n[^b]:[^b]:A\nB\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"

            """)
    }

    @Test
    func outerDuplicateInsideListItem() {
        #expect(TreeDump.dump("[^b]\n- [^b]:[^b]:A\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              list bullet '-' tight
                item
              footnote_definition "b"

            """)
    }

    @Test
    func outerDuplicateThroughBlockQuote() {
        #expect(TreeDump.dump("[^b]\n[^b]:> [^b]:A\n", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "b"
                block_quote

            """)
    }
}
