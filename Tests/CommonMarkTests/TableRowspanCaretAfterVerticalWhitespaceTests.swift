/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A `^` row-span cell preceded by a vertical tab or form feed is still a row-span marker.
@Suite("Row-span marker after vertical whitespace")
struct TableRowspanCaretAfterVerticalWhitespaceTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink,
    ]

    @Test func formFeedBeforeCaret() {
        #expect(CmarkTreeDump.dump("a\n|-\n|\u{C}^", options: Self.options) == """
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
        #expect(CmarkTreeDump.dump("a\n|-\n|\u{B}\u{C} ^", options: Self.options) == """
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
        #expect(CmarkTreeDump.dump("a|b\n-|-\nx|\u{B}^", options: Self.options) == """
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
        #expect(CmarkTreeDump.dump("a\n|-\n|\u{B}^|", options: Self.options) == """
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
        #expect(CmarkTreeDump.dump("a\n|-\n|\u{C}^ |", options: Self.options) == """
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
        #expect(CmarkTreeDump.dump("a|b\n-|-\n|\u{B}^|x", options: Self.options) == """
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

    /// A header cell has no row above to span into, so it keeps its `^` text but still carries rowspan 0.
    @Test func verticalTabBeforeCaretInHeader() {
        #expect(CmarkTreeDump.dump("|\u{B}^|\n|-|", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=0
                    text "^"

            """)
    }

    /// The row's first cell with no leading pipe is not pipe-preceded, so its leading VT is content, not padding.
    @Test func verticalTabBeforeCaretWithoutLeadingPipeStaysLiteral() {
        #expect(CmarkTreeDump.dump("a|b\n-|-\n\u{B}^|x", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "\\u{B}^"
                  table_cell align=none colspan=1 rowspan=1
                    text "x"

            """)
    }

    /// A trailing VT is content (only a pipe's leading padding absorbs VT/FF), so `^<VT>` is not a marker.
    @Test func verticalTabAfterCaretStaysLiteral() {
        #expect(CmarkTreeDump.dump("a\n|-\n|^\u{B}", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "^\\u{B}"

            """)
    }

    @Test func verticalTabBeforeCaretFlagOff() {
        #expect(CmarkTreeDump.dump("a\n|-\n|\u{B}^", options: Self.options) == """
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
