/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Once a header row and delimiter row form a table, the paragraph is gone, so a following `-` or `=` line
/// is not a setext heading underline (Setext headings): `-` starts a list and `=` is a body row.
@Suite("Table followed by a setext heading underline")
struct TableVsSetextTests {

    // MARK: - After a table

    @Test("dash underline after a table delimiter forms a table + a bullet list, not a heading")
    func dashAfterDelimiter() {
        #expect(TreeDump.dump("r\n|-\n-", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "r"
              list bullet '-' tight
                item

            """)
    }

    @Test("equals line after a table delimiter is a table body row, not a heading")
    func equalsAfterDelimiter() {
        #expect(TreeDump.dump("r\n|-\n=", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "r"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "="

            """)
    }

    @Test("multi-column table then an equals line keeps a table (body row), not a heading")
    func multiColumnEquals() {
        #expect(TreeDump.dump("a|b\n-|-\n=", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "="
                  table_cell align=none colspan=1 rowspan=1

            """)
    }

    // MARK: - Without a table

    @Test("a dash underline with no delimiter row is a setext heading")
    func plainSetextHeading() {
        #expect(TreeDump.dump("r\n-", options: .tables) == """
            document
              heading 2
                text "r"

            """)
    }

    @Test("a header + delimiter with no third line is a table")
    func bareTable() {
        #expect(TreeDump.dump("r\n|-", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "r"

            """)
    }
}
