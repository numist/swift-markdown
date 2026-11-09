/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The spaces between pipes and cell content, and the pipes themselves, are not part of a cell (Tables (extension)), so a
/// cell covers just its content, and a cell with no content has an empty range just past its opening pipe. A row runs
/// from its first byte to its closing pipe, or to its last cell's content when it has none, and a table runs from its
/// header row to its last row, or to its delimiter row when it has no body; trailing whitespace is outside all three.
@Suite("Table, row and cell source ranges")
struct TableSourceRangeTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: [.tables, .tableSpans, .sourcePosition], sourceRanges: true)
    }

    @Test
    func paddedCells() {
        #expect(tree("| a | b |\n| - | - |\n| x | y |  \n") == """
            document @1:1-4:1
              table @1:1-3:10
                table_header @1:1-1:10
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "a" @1:3-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                    text "b" @1:7-1:8
                table_row @3:1-3:10
                  table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                    text "x" @3:3-3:4
                  table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                    text "y" @3:7-3:8

            """)
    }

    @Test
    func tabPaddedCells() {
        #expect(tree("|\ta\t|\n|-|\n|\tx\t|\n") == """
            document @1:1-4:1
              table @1:1-3:6
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "a" @1:3-1:4
                table_row @3:1-3:6
                  table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                    text "x" @3:3-3:4

            """)
    }

    @Test
    func headerOnlyTableEndsAtDelimiterRow() {
        #expect(tree("| a |\n| --- |  \n") == """
            document @1:1-3:1
              table @1:1-2:8
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "a" @1:3-1:4

            """)
    }

    @Test
    func rowsWithoutOuterPipes() {
        #expect(tree("a | b\n--|--\nx | y  \n") == """
            document @1:1-4:1
              table @1:1-3:6
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                    text "b" @1:5-1:6
                table_row @3:1-3:6
                  table_cell align=none colspan=1 rowspan=1 @3:1-3:2
                    text "x" @3:1-3:2
                  table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                    text "y" @3:5-3:6

            """)
    }

    @Test
    func whitespaceOnlyAndEmptyCells() {
        #expect(tree("|a|b|c|\n|-|-|-|\n|  || x |\n") == """
            document @1:1-4:1
              table @1:1-3:10
                table_header @1:1-1:8
                  table_cell align=none colspan=1 rowspan=1 @1:2-1:3
                    text "a" @1:2-1:3
                  table_cell align=none colspan=1 rowspan=1 @1:4-1:5
                    text "b" @1:4-1:5
                  table_cell align=none colspan=1 rowspan=1 @1:6-1:7
                    text "c" @1:6-1:7
                table_row @3:1-3:10
                  table_cell align=none colspan=2 rowspan=1 @3:2-3:2
                  table_cell align=none colspan=0 rowspan=1 @3:5-3:5
                  table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                    text "x" @3:7-3:8

            """)
    }

    /// A form feed is whitespace but not a blank line, so a line holding only one is a body row with one empty cell.
    @Test
    func whitespaceOnlyLastRow() {
        #expect(tree("| a |\n|---|\n\u{0C}\n") == """
            document @1:1-4:1
              table @1:1-3:1
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "a" @1:3-1:4
                table_row @3:1-3:1
                  table_cell align=none colspan=0 rowspan=1 @3:1-3:1

            """)
    }

    /// A line before the header holding only a line tabulation stays a paragraph, with no raw content.
    @Test
    func controlWhitespaceOnlyLineBeforeHeader() {
        #expect(tree("\u{0B}\na|b\n-|-\n") == """
            document @1:1-4:1
              paragraph @1:1-1:1
              table @2:1-3:4
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "b" @2:3-2:4

            """)
    }

    @Test
    func controlWhitespaceOnlyLineBeforeHeaderInBlockQuote() {
        #expect(tree("> \u{0B}\n> a|b\n> -|-\n") == """
            document @1:1-4:1
              block_quote @1:1-3:6
                paragraph @1:3-1:3
                table @2:3-3:6
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "a" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                      text "b" @2:5-2:6

            """)
    }

    /// A form feed is padding before a row's first cell or pipe, so the row and the table start after it.
    @Test
    func formFeedBeforeRows() {
        #expect(tree("\u{0C}| a |\n|---|\n\u{0C}x\n") == """
            document @1:1-4:1
              table @1:2-3:3
                table_header @1:2-1:7
                  table_cell align=none colspan=1 rowspan=1 @1:4-1:5
                    text "a" @1:4-1:5
                table_row @3:2-3:3
                  table_cell align=none colspan=1 rowspan=1 @3:2-3:3
                    text "x" @3:2-3:3

            """)
    }

    @Test
    func rowspanMarkerCell() {
        #expect(tree("| a |\n|---|\n| ^ |\n") == """
            document @1:1-4:1
              table @1:1-3:6
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=2 @1:3-1:4
                    text "a" @1:3-1:4
                table_row @3:1-3:6
                  table_cell align=none colspan=1 rowspan=0 @3:3-3:4

            """)
    }

    @Test
    func missingCellsAfterTrailingWhitespace() {
        #expect(tree("| a | b |\n|---|---|\n| x |  \n") == """
            document @1:1-4:1
              table @1:1-3:6
                table_header @1:1-1:10
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "a" @1:3-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                    text "b" @1:7-1:8
                table_row @3:1-3:6
                  table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                    text "x" @3:3-3:4
                  table_cell align=none colspan=1 rowspan=1 @-

            """)
    }

    /// The backslash before an escaped pipe is part of the cell's content but not of the text, which holds the pipe.
    @Test
    func escapedPipeAtCellEdge() {
        #expect(tree("| \\| |\n|---|\n") == """
            document @1:1-3:1
              table @1:1-2:6
                table_header @1:1-1:7
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:5
                    text "|" @1:4-1:5

            """)
    }

    @Test
    func inlineSpanInPaddedCell() {
        #expect(tree("| *a* |\n|---|\n") == """
            document @1:1-3:1
              table @1:1-2:6
                table_header @1:1-1:8
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:6
                    emph @1:3-1:6
                      text "a" @1:4-1:5

            """)
    }

    @Test
    func tableInListItemWithTrailingWhitespace() {
        #expect(tree("- | a |  \n  |---|  \n  | x |  \n") == """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  table @1:3-3:8
                    table_header @1:3-1:8
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "a" @1:5-1:6
                    table_row @3:3-3:8
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "x" @3:5-3:6

            """)
    }
}
