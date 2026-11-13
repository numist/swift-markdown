/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// When a delimiter row follows a paragraph of several lines, the paragraph's last line is the header
/// row and the earlier lines remain a paragraph (Tables (extension)).
@Suite("Table takes a paragraph's last line as its header row")
struct TablePrecedingParagraphTests {

    // MARK: - Earlier lines remain a paragraph

    @Test("one preceding line splits off, header is the last line")
    func singlePrecedingLine() {
        #expect(TreeDump.dump("x\na\n|-", options: .tables) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("multiple preceding lines split off as one paragraph")
    func multiplePrecedingLines() {
        #expect(TreeDump.dump("x\ny\na\n|-", options: .tables) == """
            document
              paragraph
                text "x"
                softbreak
                text "y"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a body row after the delimiter joins the table")
    func precedingLineWithBodyRow() {
        #expect(TreeDump.dump("x\na\n|-\nb", options: .tables) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("multi-column header preceded by paragraph text")
    func multiColumnPreceding() {
        #expect(TreeDump.dump("x\na|b\n-|-", options: .tables) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("both-pipes single-column delimiter preceded by text")
    func precedingBothPipes() {
        #expect(TreeDump.dump("x\na\n|-|", options: .tables) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    // MARK: - Closing the table

    @Test("a lone-pipe line after the delimiter closes the table")
    func lonePipeClosesTable() {
        // A lone `|` has no cells, so it is not a body row.
        #expect(TreeDump.dump("x\na\n|-\n|", options: .tables) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
              paragraph
                text "|"

            """)
    }

    // MARK: - No earlier lines

    @Test("a header that is the paragraph's only line has no preceding paragraph")
    func bareTwoLineTable() {
        #expect(TreeDump.dump("a\n|-", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a paragraph, a blank line, then a header and delimiter row give a paragraph and a table")
    func blankLineSeparates() {
        #expect(TreeDump.dump("x\n\na\n|-", options: .tables) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a dash-only line after preceding text is a setext heading, not a table")
    func setextNotTable() {
        // A line of only dashes is a setext heading underline, which takes the whole paragraph
        // (Setext headings).
        #expect(TreeDump.dump("x\na\n-", options: .tables) == """
            document
              heading 2
                text "x"
                softbreak
                text "a"

            """)
    }

    @Test("a multi-line paragraph with no delimiter row stays one paragraph")
    func paragraphWithoutDelimiterRow() {
        #expect(TreeDump.dump("x\ny\nz", options: .tables) == """
            document
              paragraph
                text "x"
                softbreak
                text "y"
                softbreak
                text "z"

            """)
        #expect(TreeDump.dump("a|b\nc|d", options: .tables) == """
            document
              paragraph
                text "a|b"
                softbreak
                text "c|d"

            """)
    }

    // MARK: - Source ranges

    @Test("split-off paragraph and table carry source ranges", arguments: [
        ("x\na\n|-", """
            document @1:1-3:3
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:3
                table_header @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2

            """),
        ("x\ny\na\n|-", """
            document @1:1-4:3
              paragraph @1:1-2:2
                text "x" @1:1-1:2
                softbreak @-
                text "y" @2:1-2:2
              table @3:1-4:3
                table_header @3:1-3:2
                  table_cell align=none colspan=1 rowspan=1 @3:1-3:2
                    text "a" @3:1-3:2

            """),
        ("x\na\n|-\nb", """
            document @1:1-4:2
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-4:2
                table_header @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                table_row @4:1-4:2
                  table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                    text "b" @4:1-4:2

            """),
        ("x\na|b\n-|-", """
            document @1:1-3:4
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:4
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "b" @2:3-2:4

            """),
    ])
    func splitNodesSourceRanges(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: [.tables, .sourcePosition], sourceRanges: true) == tree)
    }
}
