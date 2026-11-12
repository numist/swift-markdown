/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Tables whose delimiter row has one column, such as `|-`, `-|`, `|-|` or `:-` (Tables (extension)).
/// The header row needs no pipe when its cell count matches the delimiter row's. A pipe-less line of
/// dashes under a paragraph that can be a setext heading is its underline (Setext headings) rather than a
/// delimiter row.
@Suite("Single-column GFM tables")
struct SingleColumnTableTests {

    @Test("a leading-pipe single-column delimiter row forms a table")
    func leadingPipe() {
        #expect(TreeDump.dump("a\n|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a trailing-pipe single-column delimiter row forms a table")
    func trailingPipe() {
        #expect(TreeDump.dump("a\n-|", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a both-pipes single-column delimiter row forms a table")
    func bothPipes() {
        #expect(TreeDump.dump("a\n|-|", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    /// `:-` is not a setext heading underline, so it can be a delimiter row without a pipe.
    @Test("a pipe-less colon single-column delimiter row forms a left-aligned table")
    func pipelessColonLeft() {
        #expect(TreeDump.dump("a\n:-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=left colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a pipe-less centered single-column delimiter row forms a centered table")
    func pipelessColonCenter() {
        #expect(TreeDump.dump("a\n:-:", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=center colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("single-column alignment markers set the column alignment", arguments: [
        ("a\n|:-", """
            document
              table
                table_header
                  table_cell align=left colspan=1 rowspan=1
                    text "a"

            """),
        ("a\n|-:|", """
            document
              table
                table_header
                  table_cell align=right colspan=1 rowspan=1
                    text "a"

            """),
        ("a\n|:-:|", """
            document
              table
                table_header
                  table_cell align=center colspan=1 rowspan=1
                    text "a"

            """),
    ])
    func alignmentVariants(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.tables]) == tree)
    }

    @Test("a single-column table carries body rows")
    func bodyRows() {
        #expect(TreeDump.dump("a\n|-|\nb\nc", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "c"

            """)
    }

    @Test("a single-column table nested in a block quote forms")
    func nestedBlockQuoteSingleColumn() {
        #expect(TreeDump.dump("> a\n> :-", options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=left colspan=1 rowspan=1
                      text "a"

            """)
    }

    @Test("a pipe-less dash-only second line stays a setext heading, not a table", arguments: [
        ("a\n-", """
            document
              heading 2
                text "a"

            """),
        ("a\n--", """
            document
              heading 2
                text "a"

            """),
        ("a\n---", """
            document
              heading 2
                text "a"

            """),
    ])
    func pipelessDashIsSetext(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.tables]) == tree)
    }

    @Test("a second line that is not a delimiter row stays a paragraph", arguments: [
        ("a\nb", """
            document
              paragraph
                text "a"
                softbreak
                text "b"

            """),
        ("a|b\nc|d", """
            document
              paragraph
                text "a|b"
                softbreak
                text "c|d"

            """),
    ])
    func nonDelimiterStaysParagraph(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.tables]) == tree)
    }

    @Test("a multi-column table forms")
    func multiColumn() {
        #expect(TreeDump.dump("a|b\n-|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    /// Like a setext heading underline, a delimiter row may be indented at most 3 columns; a more indented one is
    /// paragraph continuation text. A leading tab is 4 columns (Tabs).
    @Test("a delimiter row indented 4+ columns is not a table", arguments: [
        ("o\n\t-", """
            document
              paragraph
                text "o"
                softbreak
                text "-"

            """),
        ("o\n    -", """
            document
              paragraph
                text "o"
                softbreak
                text "-"

            """),
        ("o\n    |-", """
            document
              paragraph
                text "o"
                softbreak
                text "|-"

            """),
        ("o\n\t---", """
            document
              paragraph
                text "o"
                softbreak
                text "---"

            """),
        ("o\n\t|-", """
            document
              paragraph
                text "o"
                softbreak
                text "|-"

            """),
        ("Foo\n    ---", """
            document
              paragraph
                text "Foo"
                softbreak
                text "---"

            """),
    ])
    func indentedDelimiterStaysParagraph(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.tables]) == tree)
    }

    @Test("a delimiter row indented fewer than 4 columns forms a table", arguments: [
        ("a\n   |-", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """),
        ("a\n  :-:", """
            document
              table
                table_header
                  table_cell align=center colspan=1 rowspan=1
                    text "a"

            """),
        ("a\n :-", """
            document
              table
                table_header
                  table_cell align=left colspan=1 rowspan=1
                    text "a"

            """),
    ])
    func underIndentedDelimiterFormsTable(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.tables]) == tree)
    }
}
