/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A rowspan marker cell extends the nearest cell above it that isn't a marker cell. A header marker cell has no row
/// above, so it and the marker cells directly below it extend nothing: each keeps its marker text with rowspan 0. Empty
/// cells count toward the colspan of the nearest non-empty cell to their left, even when that cell is past the last
/// column, and the ditto marker needs table spans.
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
