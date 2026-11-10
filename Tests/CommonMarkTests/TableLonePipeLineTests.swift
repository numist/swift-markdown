/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A line holding only a leading pipe (Tables (extension)), optionally with whitespace, has no cells. It
/// is not a body row, so it closes the table and starts a paragraph.
@Suite("A lone-pipe line ends the table")
struct TableLonePipeLineTests {

    // MARK: - Lone pipe

    @Test("a lone-pipe line after a single-column header row is not a body row")
    func lonePipeLineSingleColumn() {
        #expect(TreeDump.dump("f\n|-\n|", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "f"
              paragraph
                text "|"

            """)
    }

    @Test("a lone-pipe line after a multi-column header row is not a body row")
    func lonePipeLineMultiColumn() {
        #expect(TreeDump.dump("a|b\n-|-\n|", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
              paragraph
                text "|"

            """)
    }

    // MARK: - Rows with cells

    @Test("a leading+trailing pipe body row is one empty cell, kept as a table row")
    func doublePipeBodyRowStaysARow() {
        #expect(TreeDump.dump("f\n|-\n||", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "f"
                table_row
                  table_cell align=none colspan=1 rowspan=1

            """)
    }
}
