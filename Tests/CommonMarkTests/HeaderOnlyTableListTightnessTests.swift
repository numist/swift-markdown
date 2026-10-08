/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A table whose delimiter row is its last row ends no differently from any other table, so with no blank line
/// separating a list's items or blocks the list stays tight (Lists). A line holding only a pipe is not a table row; it
/// ends the table and starts a paragraph.
@Suite("List tightness around a header-only table")
struct HeaderOnlyTableListTightnessTests {

    @Test("a header-only table followed by a pipe-only line")
    func pipeOnlyLine() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  |\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
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

    @Test("a header-only table followed by a pipe and a space")
    func pipeAndSpaceLine() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  | \n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
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

    @Test("a pipe-only line after a header-only table, then the next item")
    func pipeOnlyLineThenItem() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  |\n- c\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                  paragraph
                    text "|"
                item
                  paragraph
                    text "c"

            """)
    }

    @Test("a pipe-only line after a header-only table, continued by a paragraph line")
    func pipeOnlyLineThenContinuation() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  |\n  d\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                  paragraph
                    text "|"
                    softbreak
                    text "d"

            """)
    }

    @Test("an ordered list in the same shape")
    func orderedList() {
        #expect(TreeDump.dump("1. a|b\n   -|-\n   |\n", options: [.tables]) == """
            document
              list ordered start=1 delim=period tight
                item
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

    @Test("a nested list in the same shape")
    func nestedList() {
        #expect(TreeDump.dump("- - a|b\n    -|-\n    |\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  list bullet '-' tight
                    item
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

    @Test("a header-only table followed by the next item")
    func headerOnlyTableThenItem() {
        #expect(TreeDump.dump("- a|b\n  -|-\n- c\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                item
                  paragraph
                    text "c"

            """)
    }

    @Test("a header-only table followed by a heading in the same item")
    func headerOnlyTableThenHeading() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  # h\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                  heading 1
                    text "h"

            """)
    }

    @Test("a header-only table followed by a block quote in the same item")
    func headerOnlyTableThenBlockQuote() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  > q\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                  block_quote
                    paragraph
                      text "q"

            """)
    }

    @Test("a table with a body row followed by the next item")
    func bodyRowThenItem() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  c|d\n- e\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                    table_row
                      table_cell align=none colspan=1 rowspan=1
                        text "c"
                      table_cell align=none colspan=1 rowspan=1
                        text "d"
                item
                  paragraph
                    text "e"

            """)
    }

    @Test("a table with a body row followed by a pipe-only line")
    func bodyRowThenPipeOnlyLine() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  c|d\n  |\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                    table_row
                      table_cell align=none colspan=1 rowspan=1
                        text "c"
                      table_cell align=none colspan=1 rowspan=1
                        text "d"
                  paragraph
                    text "|"

            """)
    }

    @Test("a header-only table followed by a body row starting with a pipe")
    func pipeLineWithContent() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  | x\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
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

    @Test("a header-only table followed by a body row without pipes")
    func paragraphLine() {
        #expect(TreeDump.dump("- a|b\n  -|-\n  x\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
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

    @Test("a header-only table alone")
    func headerOnlyTable() {
        #expect(TreeDump.dump("- a|b\n  -|-\n", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
    }
}
