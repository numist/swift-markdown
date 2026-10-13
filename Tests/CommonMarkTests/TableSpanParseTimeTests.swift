/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parse time for long runs of spanning cells with `.tableSpans`.
///
/// A rowspan marker grows the nearest cell above it that isn't itself a marker, and an empty cell grows the nearest
/// cell to its left that isn't itself empty. Finding that cell must not walk up past every marker above, or left past
/// every empty cell.
@Suite("Spanning table cells parse in linear time")
struct TableSpanParseTimeTests {

    struct Shape: Sendable, CustomTestStringConvertible {
        let options: MarkdownDocument.ParseOptions
        let make: @Sendable (Int) -> String
        let testDescription: String
    }

    static let shapes: [Shape] = [
        Shape(options: [.tables, .tableSpans], make: { "|a|b|\n|-|-|\n|x|y|\n" + String(repeating: "|^|^|\n", count: $0) }, testDescription: "rowspan markers"),
        Shape(options: [.tables, .tableSpans, .tableRowspanDitto], make: { "|a|b|\n|-|-|\n|x|y|\n" + String(repeating: "|\"|\"|\n", count: $0) }, testDescription: "ditto rowspan markers"),
        Shape(options: [.tables, .tableSpans], make: { "|a|b|\n|-|-|\n|x" + String(repeating: "|", count: 4 * $0) + "\n" }, testDescription: "empty cells"),
    ]

    /// The top cell spans the whole column of markers below it, and the cells of the marker rows are fillers.
    @Test("a column of rowspan markers grows the cell above them")
    func rowspanTree() {
        #expect(TreeDump.dump("|a|\n|-|\n|x|\n|^|\n|^|\n", options: [.tables, .tableSpans]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=3
                    text "x"
                table_row
                  table_cell align=none colspan=1 rowspan=0
                table_row
                  table_cell align=none colspan=1 rowspan=0

            """)
    }

    /// The first cell spans every empty cell after it, past the column count.
    @Test("a row of empty cells grows the cell before them")
    func colspanTree() {
        #expect(TreeDump.dump("|a|b|\n|-|-|\n|x||||\n", options: [.tables, .tableSpans]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=4 rowspan=1
                    text "x"
                  table_cell align=none colspan=0 rowspan=1

            """)
    }

    @Test("a long run of spanning cells parses in linear time", arguments: shapes)
    func longRun(_ shape: Shape) {
        expectLinearParseTime(count: 2000, options: shape.options, shape.make)
    }
}
