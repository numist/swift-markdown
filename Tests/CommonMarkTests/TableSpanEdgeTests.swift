/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// A header marker cell has no row above to extend, so it and the marker cells directly below it extend nothing
// and keep their marker text with rowspan 0.
@Suite("Table span cells at the table's edges")
struct TableSpanEdgeTests {
    private static let spans: MarkdownDocument.ParseOptions = [.tables, .tableSpans]

    @Test
    func headerMarkerAndMarkerBelowKeepTheirText() {
        #expect(TreeDump.dump("^|a\n-|-\n^|b\n", options: Self.spans) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=0
                    text "^"
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0
                    text "^"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test
    func headerDittoAndDittoBelowKeepTheirText() {
        #expect(TreeDump.dump("\"|a\n-|-\n\"|b\n", options: Self.spans.union(.tableRowspanDitto)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=0
                    text "\\""
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=0
                    text "\\""
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test
    func markerBelowHeaderCellExtendsIt() {
        #expect(TreeDump.dump("a|b\n-|-\n^|c\n", options: Self.spans) == """
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
                    text "c"

            """)
    }

    @Test
    func markerBelowCellUnderHeaderMarkerExtendsThatCell() {
        #expect(TreeDump.dump("^|a\n-|-\nx|b\n^|c\n", options: Self.spans) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=0
                    text "^"
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=2
                    text "x"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=0
                  table_cell align=none colspan=1 rowspan=1
                    text "c"

            """)
    }

    @Test
    func dittoWithoutTableSpansIsText() {
        #expect(TreeDump.dump("x|a\n-|-\n\"|b\n", options: [.tables, .tableRowspanDitto]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "\\""
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test
    func emptyCellAfterCellPastLastColumnExtendsNoKeptCell() {
        #expect(TreeDump.dump("a|b\n-|-\nx|y|z||\n", options: Self.spans) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                  table_cell align=none colspan=1 rowspan=1
                    text "y"

            """)
    }
}
