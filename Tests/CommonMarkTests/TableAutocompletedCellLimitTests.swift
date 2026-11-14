/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// `maxTableAutocompletedCells` bounds the empty cells a table inserts into body rows with fewer cells than the header
/// row (Tables (extension)). Each body row adds the cells it is short of the header's width; a row with as many cells or
/// more adds none. A body row is not part of the table once the rows before it added more than the limit: it ends the
/// table and starts a paragraph.
@Suite("Table autocompleted cell limit")
struct TableAutocompletedCellLimitTests {

    private func limits(_ cells: Int) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxTableAutocompletedCells = cells
        return limits
    }

    private let header = """
        table_header
              table_cell align=none colspan=1 rowspan=1
                text "a"
              table_cell align=none colspan=1 rowspan=1
                text "b"
              table_cell align=none colspan=1 rowspan=1
                text "c"
        """

    /// A body row of one cell holding `text`, and the two cells inserted after it.
    private func paddedRow(_ text: String) -> String {
        """
            table_row
              table_cell align=none colspan=1 rowspan=1
                text "\(text)"
              table_cell align=none colspan=1 rowspan=1
              table_cell align=none colspan=1 rowspan=1
        """
    }

    @Test("a body row after rows that added as many cells as the limit is a row")
    func rowAfterRowsAtLimit() {
        #expect(TreeDump.dump("a|b|c\n-|-|-\nx\ny\nz", options: .tables, limits: limits(4)) == """
            document
              table
                \(header)
            \(paddedRow("x"))
            \(paddedRow("y"))
            \(paddedRow("z"))

            """)
    }

    @Test("a body row after rows that added one cell more than the limit ends the table and starts a paragraph")
    func rowAfterRowsPastLimit() {
        #expect(TreeDump.dump("a|b|c\n-|-|-\nx\ny\nz\nw", options: [.tables, .sourcePosition], limits: limits(3), sourceRanges: true) == """
            document @1:1-6:2
              table @1:1-4:2
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "b" @1:3-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                    text "c" @1:5-1:6
                table_row @3:1-3:2
                  table_cell align=none colspan=1 rowspan=1 @3:1-3:2
                    text "x" @3:1-3:2
                  table_cell align=none colspan=1 rowspan=1 @-
                  table_cell align=none colspan=1 rowspan=1 @-
                table_row @4:1-4:2
                  table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                    text "y" @4:1-4:2
                  table_cell align=none colspan=1 rowspan=1 @-
                  table_cell align=none colspan=1 rowspan=1 @-
              paragraph @5:1-6:2
                text "z" @5:1-5:2
                softbreak @-
                text "w" @6:1-6:2

            """)
    }

    @Test("the header and delimiter rows add no cells, so a limit of zero or less keeps the first body row", arguments: [0, -1])
    func firstBodyRowAtZero(_ cells: Int) {
        #expect(TreeDump.dump("a|b|c\n-|-|-\nx\ny", options: .tables, limits: limits(cells)) == """
            document
              table
                \(header)
            \(paddedRow("x"))
              paragraph
                text "y"

            """)
    }

    @Test("a row with more cells than the header adds none and takes none away")
    func widerRowAddsNone() {
        #expect(TreeDump.dump("a|b|c\n-|-|-\nv|v|v|v|v\nx\ny\nz", options: .tables, limits: limits(2)) == """
            document
              table
                \(header)
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "v"
                  table_cell align=none colspan=1 rowspan=1
                    text "v"
                  table_cell align=none colspan=1 rowspan=1
                    text "v"
            \(paddedRow("x"))
            \(paddedRow("y"))
              paragraph
                text "z"

            """)
    }

    @Test("empty cells in the source are not inserted cells")
    func emptySourceCellsAddNone() {
        #expect(TreeDump.dump("a|b|c\n-|-|-\n| | | |\nx\ny", options: .tables, limits: limits(0)) == """
            document
              table
                \(header)
                table_row
                  table_cell align=none colspan=1 rowspan=1
                  table_cell align=none colspan=1 rowspan=1
                  table_cell align=none colspan=1 rowspan=1
            \(paddedRow("x"))
              paragraph
                text "y"

            """)
    }

    @Test("a row short of the header by one cell adds one")
    func rowShortByOne() {
        let source = "a|b|c\n-|-|-\nx|x\nx|x\ny"
        let row = """
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                  table_cell align=none colspan=1 rowspan=1
            """
        #expect(TreeDump.dump(source, options: .tables, limits: limits(0)) == """
            document
              table
                \(header)
            \(row)
              paragraph
                text "x|x"
                softbreak
                text "y"

            """)
        #expect(TreeDump.dump(source, options: .tables, limits: limits(1)) == """
            document
              table
                \(header)
            \(row)
            \(row)
              paragraph
                text "y"

            """)
    }

    @Test("the paragraph a refused body row starts can be a setext heading")
    func refusedRowUnderlined() {
        #expect(TreeDump.dump("a|b|c\n-|-|-\nx\ny\n-", options: .tables, limits: limits(0)) == """
            document
              table
                \(header)
            \(paddedRow("x"))
              heading 2
                text "y"

            """)
    }

    @Test("the default limits insert a million cells")
    func defaultLimitsAtScale() {
        let source = "|" + String(repeating: "a|", count: 1001) + "\n|" + String(repeating: "-|", count: 1001) + "\n"
            + String(repeating: "x\n", count: 1000)
        let tree = TreeDump.dump(source, options: .tables)
        #expect(tree.hasPrefix("document\n  table\n"))
        #expect(!tree.contains("paragraph"))
        #expect(tree.components(separatedBy: "table_row").count - 1 == 1000)
        #expect(tree.components(separatedBy: "table_cell").count - 1 == 1_002_001)
    }

    @Test("the default limits insert any number of cells")
    func defaultLimits() {
        #expect(TreeDump.dump("a|b|c\n-|-|-\nx\ny\nz", options: .tables) == """
            document
              table
                \(header)
            \(paddedRow("x"))
            \(paddedRow("y"))
            \(paddedRow("z"))

            """)
    }
}
