/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A `^` row-span cell grows the cell above it, whether that cell is parsed from the source (non-empty,
/// whitespace-only, or a zero-width `||` colspan filler) or padded in for a row with fewer cells than the table has
/// columns.
@Suite("Row span into a padded cell")
struct TableRowspanIntoPaddedCellTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink,
    ]

    /// Flag-off (shipped): the cell padded in after `x|`'s row-ending pipe absorbs the span below it like a
    /// parsed cell, where cmark gives a padded cell no span data.
    @Test func explicitEmptyCellAboveCaretGrowsFlagOff() {
        #expect(CmarkTreeDump.dump("a|b\n-|-\nx|\ny|^", options: Self.options) == """
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
                  table_cell align=none colspan=1 rowspan=2
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "y"
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    @Test func nonEmptyCellAboveCaretControl() {
        #expect(CmarkTreeDump.dump("a|b\n-|-\nx|z\ny|^\nw|^", options: Self.options) == """
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
                  table_cell align=none colspan=1 rowspan=3
                    text "z"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "y"
                  table_cell align=none colspan=1 rowspan=0
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "w"
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    /// Flag-off (shipped): the padded cell absorbs both spans below it like a parsed cell, where cmark
    /// gives a padded cell no span data.
    @Test func paddedCellAboveSeveralCaretsGrowsFlagOff() {
        #expect(CmarkTreeDump.dump("a|b\n-|-\nx\ny|^\nw|^", options: Self.options) == """
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
                  table_cell align=none colspan=1 rowspan=3
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "y"
                  table_cell align=none colspan=1 rowspan=0
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "w"
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    /// Flag-off (shipped): each padded cell absorbs the span below it like a parsed cell, where cmark gives
    /// a padded cell no span data.
    @Test func severalPaddedCellsAboveCaretsGrowFlagOff() {
        #expect(CmarkTreeDump.dump("a|b|c\n-|-|-\nx\ny|^|^", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                  table_cell align=none colspan=1 rowspan=2
                  table_cell align=none colspan=1 rowspan=2
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "y"
                  table_cell align=none colspan=1 rowspan=0
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    /// A parsed cell that is empty (here whitespace-only, in the header) is a real cell, so it does grow.
    @Test func parsedEmptyHeaderCellAboveCaretGrows() {
        #expect(CmarkTreeDump.dump("| |b\n-|-\n^|x", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=2
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=0
                  table_cell align=none colspan=1 rowspan=1
                    text "x"

            """)
    }

    /// Flag-off (shipped): the padded cell absorbs the span below it, as a parsed cell would.
    @Test func paddedCellAboveCaretGrowsFlagOff() {
        #expect(CmarkTreeDump.dump("a|b\n-|-\nx\ny|^", options: Self.options) == """
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
                  table_cell align=none colspan=1 rowspan=2
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "y"
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    /// Flag-off (shipped): a padded cell still stops the upward scan, and grows instead of the cell above it.
    @Test func paddedCellInterruptsEarlierSpanFlagOff() {
        #expect(CmarkTreeDump.dump("a|b\n-|-\nx|z\ny|^\nw\nv|^", options: Self.options) == """
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
                  table_cell align=none colspan=1 rowspan=2
                    text "z"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "y"
                  table_cell align=none colspan=1 rowspan=0
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "w"
                  table_cell align=none colspan=1 rowspan=2
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "v"
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    /// Flag-off (shipped): both the colspan filler and the padded cell beside it grow.
    @Test func colspanFillerAndPaddedCellAboveCaretsGrowFlagOff() {
        #expect(CmarkTreeDump.dump("a|b|c\n-|-|-\nx||\ny|^|^", options: Self.options) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                table_row
                  table_cell align=none colspan=2 rowspan=1
                    text "x"
                  table_cell align=none colspan=0 rowspan=2
                  table_cell align=none colspan=1 rowspan=2
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "y"
                  table_cell align=none colspan=1 rowspan=0
                  table_cell align=none colspan=1 rowspan=0

            """)
    }
}
