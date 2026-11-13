/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Long runs of spanning table cells.
///
/// A `^` cell, or with ditto row spans a `"` cell instead, extends the nearest cell above it that is not itself a span
/// marker, and a cell with nothing between its pipes extends the nearest cell to its left that is not itself such a
/// cell. 160,000 rows of markers, or a row of 160,000 pipes after one cell, parse well within the time limit.
@Suite("Runs of spanning table cells")
struct SpanningTableCellRunTests {
    private static let spans: MarkdownDocument.ParseOptions = [.tables, .tableSpans]

    private static func markerRows(_ count: Int) -> String {
        String(repeating: """
                table_row
                  table_cell align=none colspan=1 rowspan=0
                  table_cell align=none colspan=1 rowspan=0

            """, count: count)
    }

    private static func rowspanTree(rows: Int) -> String {
        """
        document
          table
            table_header
              table_cell align=none colspan=1 rowspan=1
                text "a"
              table_cell align=none colspan=1 rowspan=1
                text "b"
            table_row
              table_cell align=none colspan=1 rowspan=\(rows + 1)
                text "x"
              table_cell align=none colspan=1 rowspan=\(rows + 1)
                text "y"

        """ + markerRows(rows)
    }

    private static func colspanTree(pipes: Int) -> String {
        """
        document
          table
            table_header
              table_cell align=none colspan=1 rowspan=1
                text "a"
              table_cell align=none colspan=1 rowspan=1
                text "b"
            table_row
              table_cell align=none colspan=\(pipes) rowspan=1
                text "x"
              table_cell align=none colspan=0 rowspan=1

        """
    }

    @Test
    func rowspanMarkersExtendCellAbove() {
        #expect(TreeDump.dump("|a|b|\n|-|-|\n|x|y|\n|^|^|\n|^|^|\n", options: Self.spans) == Self.rowspanTree(rows: 2))
    }

    @Test
    func dittoMarkersExtendCellAbove() {
        #expect(TreeDump.dump("|a|b|\n|-|-|\n|x|y|\n|\"|\"|\n|\"|\"|\n", options: Self.spans.union(.tableRowspanDitto)) == Self.rowspanTree(rows: 2))
    }

    @Test
    func dittoWithoutDittoRowSpansIsText() {
        #expect(TreeDump.dump("|a|\n|-|\n|x|\n|\"|\n", options: Self.spans) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "\\""

            """)
    }

    @Test
    func caretWithDittoRowSpansIsText() {
        #expect(TreeDump.dump("|a|\n|-|\n|x|\n|^|\n", options: Self.spans.union(.tableRowspanDitto)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "^"

            """)
    }

    @Test
    func emptyCellsExtendCellBefore() {
        #expect(TreeDump.dump("|a|b|\n|-|-|\n|x||||\n", options: Self.spans) == Self.colspanTree(pipes: 4))
    }

    @Test
    func whitespaceCellsDoNotExtendCellBefore() {
        #expect(TreeDump.dump("|a|b|\n|-|-|\n|x| | | |\n", options: Self.spans) == """
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

            """)
    }

    @Test(.timeLimit(.minutes(1)))
    func manyRowspanMarkerRows() {
        let source = "|a|b|\n|-|-|\n|x|y|\n" + String(repeating: "|^|^|\n", count: 160_000)
        #expect(TreeDump.dump(source, options: Self.spans) == Self.rowspanTree(rows: 160_000))
    }

    @Test(.timeLimit(.minutes(1)))
    func manyDittoMarkerRows() {
        let source = "|a|b|\n|-|-|\n|x|y|\n" + String(repeating: "|\"|\"|\n", count: 160_000)
        #expect(TreeDump.dump(source, options: Self.spans.union(.tableRowspanDitto)) == Self.rowspanTree(rows: 160_000))
    }

    @Test(.timeLimit(.minutes(1)))
    func manyEmptyCells() {
        let source = "|a|b|\n|-|-|\n|x" + String(repeating: "|", count: 160_000) + "\n"
        #expect(TreeDump.dump(source, options: Self.spans) == Self.colspanTree(pipes: 160_000))
    }
}
