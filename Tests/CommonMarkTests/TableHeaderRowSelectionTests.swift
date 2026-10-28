/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A table's header row is the line immediately before its delimiter row, and the header and delimiter rows must have
/// the same number of cells (Tables (extension)). The lines before the header remain a paragraph. These cases place the
/// rows in a top-level paragraph, a block quote, a list item, a paragraph with CRLF line endings, and a block quote
/// whose marker is followed by a tab.
@Suite("A table takes the line before its delimiter row as its header row")
struct TableHeaderRowSelectionTests {

    @Test("the lines before the header stay a paragraph: top level")
    func precedingLineSplitsOffTopLevel() {
        let source = "x\na|b\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
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
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:4
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:4
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "b" @2:3-2:4

            """)
    }

    @Test("the lines before the header stay a paragraph: block quote")
    func precedingLineSplitsOffInBlockQuote() {
        let source = "> x\n> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:6
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "a" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                      text "b" @2:5-2:6

            """)
    }

    @Test("the lines before the header stay a paragraph: list item")
    func precedingLineSplitsOffInListItem() {
        let source = "- x\n  a|b\n  -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:6
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:3-3:6
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "a" @2:3-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "b" @2:5-2:6

            """)
    }

    @Test("the lines before the header stay a paragraph: CRLF")
    func precedingLineSplitsOffWithCRLF() {
        let source = "x\r\na|b\r\n-|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
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
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:4
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:4
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "b" @2:3-2:4

            """)
    }

    @Test("the lines before the header stay a paragraph: tab after the block quote marker")
    func precedingLineSplitsOffAfterQuoteTab() {
        let source = ">\tx\n>\ta|b\n>\t-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:6
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "a" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                      text "b" @2:5-2:6

            """)
    }

    @Test("a header and delimiter that differ in cell count form no table: top level")
    func headerCellCountMismatchTopLevel() {
        let source = "x\na|b|c\n-|-\nd|e\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
                softbreak
                text "a|b|c"
                softbreak
                text "-|-"
                softbreak
                text "d|e"
                softbreak
                text "-|-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:4
              paragraph @1:1-5:4
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
                softbreak @-
                text "d|e" @4:1-4:4
                softbreak @-
                text "-|-" @5:1-5:4

            """)
    }

    @Test("a header and delimiter that differ in cell count form no table: block quote")
    func headerCellCountMismatchInBlockQuote() {
        let source = "> x\n> a|b|c\n> -|-\n> d|e\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "a|b|c"
                  softbreak
                  text "-|-"
                  softbreak
                  text "d|e"
                  softbreak
                  text "-|-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:6
              block_quote @1:1-5:6
                paragraph @1:3-5:6
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                  softbreak @-
                  text "d|e" @4:3-4:6
                  softbreak @-
                  text "-|-" @5:3-5:6

            """)
    }

    @Test("a header and delimiter that differ in cell count form no table: list item")
    func headerCellCountMismatchInListItem() {
        let source = "- x\n  a|b|c\n  -|-\n  d|e\n  -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                    softbreak
                    text "a|b|c"
                    softbreak
                    text "-|-"
                    softbreak
                    text "d|e"
                    softbreak
                    text "-|-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:6
              list bullet '-' tight @1:1-5:6
                item @1:1-5:6
                  paragraph @1:3-5:6
                    text "x" @1:3-1:4
                    softbreak @-
                    text "a|b|c" @2:3-2:8
                    softbreak @-
                    text "-|-" @3:3-3:6
                    softbreak @-
                    text "d|e" @4:3-4:6
                    softbreak @-
                    text "-|-" @5:3-5:6

            """)
    }

    @Test("a header and delimiter that differ in cell count form no table: CRLF")
    func headerCellCountMismatchWithCRLF() {
        let source = "x\r\na|b|c\r\n-|-\r\nd|e\r\n-|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
                softbreak
                text "a|b|c"
                softbreak
                text "-|-"
                softbreak
                text "d|e"
                softbreak
                text "-|-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:4
              paragraph @1:1-5:4
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
                softbreak @-
                text "d|e" @4:1-4:4
                softbreak @-
                text "-|-" @5:1-5:4

            """)
    }

    @Test("a header and delimiter that differ in cell count form no table: tab after the block quote marker")
    func headerCellCountMismatchAfterQuoteTab() {
        let source = ">\tx\n>\ta|b|c\n>\t-|-\n>\td|e\n>\t-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "a|b|c"
                  softbreak
                  text "-|-"
                  softbreak
                  text "d|e"
                  softbreak
                  text "-|-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:6
              block_quote @1:1-5:6
                paragraph @1:3-5:6
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                  softbreak @-
                  text "d|e" @4:3-4:6
                  softbreak @-
                  text "-|-" @5:3-5:6

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: top level")
    func notDelimiterRowThenDelimiterRowTopLevel() {
        let source = "x\n-:-\n|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:3
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:4
                    text "-:-" @2:1-2:4

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: block quote")
    func notDelimiterRowThenDelimiterRowInBlockQuote() {
        let source = "> x\n> -:-\n> |-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:5
              block_quote @1:1-3:5
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:5
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:6
                      text "-:-" @2:3-2:6

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: list item")
    func notDelimiterRowThenDelimiterRowInListItem() {
        let source = "- x\n  -:-\n  |-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:5
              list bullet '-' tight @1:1-3:5
                item @1:1-3:5
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:3-3:5
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:6
                        text "-:-" @2:3-2:6

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: CRLF")
    func notDelimiterRowThenDelimiterRowWithCRLF() {
        let source = "x\r\n-:-\r\n|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:3
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:4
                    text "-:-" @2:1-2:4

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: tab after the block quote marker")
    func notDelimiterRowThenDelimiterRowAfterQuoteTab() {
        let source = ">\tx\n>\t-:-\n>\t|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:5
              block_quote @1:1-3:5
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:5
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:6
                      text "-:-" @2:3-2:6

            """)
    }

    @Test("the paragraph is only the header row: top level")
    func headerOnlyTopLevel() {
        let source = "a|b\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              table @1:1-2:4
                table_header @1:1-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "b" @1:3-1:4

            """)
    }

    @Test("the paragraph is only the header row: block quote")
    func headerOnlyInBlockQuote() {
        let source = "> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:6
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "a" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "b" @1:5-1:6

            """)
    }

    @Test("the paragraph is only the header row: list item")
    func headerOnlyInListItem() {
        let source = "- a|b\n  -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
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
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:6
              list bullet '-' tight @1:1-2:6
                item @1:1-2:6
                  table @1:3-2:6
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "a" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "b" @1:5-1:6

            """)
    }

    @Test("the paragraph is only the header row: CRLF")
    func headerOnlyWithCRLF() {
        let source = "a|b\r\n-|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              table @1:1-2:4
                table_header @1:1-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "b" @1:3-1:4

            """)
    }

    @Test("the paragraph is only the header row: tab after the block quote marker")
    func headerOnlyAfterQuoteTab() {
        let source = ">\ta|b\n>\t-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:6
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "a" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "b" @1:5-1:6

            """)
    }

    @Test("NUL in the header row: top level")
    func nulInHeaderTopLevel() {
        let source = "x\na|b\u{0}\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b\u{FFFD}"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:4
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:4
                table_header @2:1-2:5
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:5
                    text "b\u{FFFD}" @2:3-2:5

            """)
    }

    @Test("NUL in the header row: block quote")
    func nulInHeaderInBlockQuote() {
        let source = "> x\n> a|b\u{0}\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b\u{FFFD}"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:6
                  table_header @2:3-2:7
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "a" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:7
                      text "b\u{FFFD}" @2:5-2:7

            """)
    }
}
