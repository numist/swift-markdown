/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A `^` row-span cell padded by a line tabulation or form feed is a row-span marker.
@Suite("Row-span marker after vertical whitespace")
struct TableRowspanCaretAfterVerticalWhitespaceTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink,
    ]

    @Test func formFeedBeforeCaret() {
        #expect(TreeDump.dump("a\n|-\n|\u{C}^", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    @Test func mixedWhitespaceBeforeCaret() {
        #expect(TreeDump.dump("a\n|-\n|\u{B}\u{C} ^", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    @Test func verticalTabBeforeCaretInSecondColumn() {
        #expect(TreeDump.dump("a|b\n-|-\nx|\u{B}^", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=2
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    @Test func verticalTabBeforeCaretWithClosingPipe() {
        #expect(TreeDump.dump("a\n|-\n|\u{B}^|", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    @Test func formFeedBeforeCaretWithPaddedClosingPipe() {
        #expect(TreeDump.dump("a\n|-\n|\u{C}^ |", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    @Test func verticalTabBeforeCaretInFirstColumnOfTwo() {
        #expect(TreeDump.dump("a|b\n-|-\n|\u{B}^|x", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=0
                  table_cell align=none colspan=1 rowspan=1
                    text "x"

            """)
    }

    /// A header cell has no row above to span into, so it keeps its `^` text while carrying rowspan 0.
    @Test func verticalTabBeforeCaretInHeader() {
        #expect(TreeDump.dump("|\u{B}^|\n|-|", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=0
                    text "^"

            """)
    }

    @Test func verticalTabBeforeCaretWithoutLeadingPipe() {
        #expect(TreeDump.dump("a|b\n-|-\n\u{B}^|x", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=0
                  table_cell align=none colspan=1 rowspan=1
                    text "x"

            """)
    }

    @Test func verticalTabAfterCaret() {
        #expect(TreeDump.dump("a\n|-\n|^\u{B}", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    @Test func verticalTabBeforeCaret() {
        #expect(TreeDump.dump("a\n|-\n|\u{B}^", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0

            """)
    }
}
