/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A paragraph whose content is only link reference definitions is still a paragraph while the next line is read, so
/// a line of `=` or `-` that cannot interrupt a paragraph continues it and a following line continues it again
/// (Link reference definitions, Setext headings, Paragraphs). A table takes the last line before its delimiter row as
/// its header row, and the earlier lines stay a paragraph (Tables (extension)). A setext heading takes the lines that
/// remain after the definitions.
@Suite("A paragraph holding only definitions continues")
struct ParagraphOfDefinitionsContinuationTests {

    @Test("a continuation line follows the underline text in a block quote")
    func quotedDefinitionsThenUnderlineThenText() {
        let source = "> [a]:\n> /u\n> ===\n> x\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:4
              block_quote @1:1-4:4
                paragraph @3:3-4:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x" @4:3-4:4

            """)
    }

    @Test("a continuation line after a tab-expanded block quote marker")
    func tabExpandedPrefixContinuation() {
        let source = ">\t[a]:\n>\t/u\n>\t===\n>\tx\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:4
              block_quote @1:1-4:4
                paragraph @3:3-4:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x" @4:3-4:4

            """)
    }

    @Test("a table header takes the last line after the continued paragraph")
    func tableAfterContinuedParagraph() {
        let source = "> [a]:\n> /u\n> ===\n> x\n> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:6
              block_quote @1:1-6:6
                paragraph @3:3-4:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x" @4:3-4:4
                table @5:3-6:6
                  table_header @5:3-5:6
                    table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                      text "a" @5:3-5:4
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                      text "b" @5:5-5:6

            """)
    }

    @Test("NUL in the continued paragraph becomes U+FFFD")
    func nulInContinuedParagraph() {
        let source = "> [a]:\n> /u\n> ===\n> x\u{0}\n> y\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x\u{FFFD}"
                  softbreak
                  text "y"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:4
              block_quote @1:1-5:4
                paragraph @3:3-5:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x\u{FFFD}" @4:3-4:5
                  softbreak @-
                  text "y" @5:3-5:4

            """)
    }

    @Test("definitions followed by a two-line setext heading in a block quote")
    func setextHeadingAfterQuotedDefinition() {
        let source = "> [a]: /u\n> foo\n> bar\n> ===\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                heading 1
                  text "foo"
                  softbreak
                  text "bar"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:6
              block_quote @1:1-4:6
                heading 1 @2:3-4:6
                  text "foo" @2:3-2:6
                  softbreak @-
                  text "bar" @3:3-3:6

            """)
    }

    @Test("NUL in a setext heading after definitions")
    func nulInSetextHeading() {
        let source = "> [a]: /u\n> fo\u{0}o\n> bar\n> ---\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                heading 2
                  text "fo\u{FFFD}o"
                  softbreak
                  text "bar"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:6
              block_quote @1:1-4:6
                heading 2 @2:3-4:6
                  text "fo\u{FFFD}o" @2:3-2:7
                  softbreak @-
                  text "bar" @3:3-3:6

            """)
    }

    @Test("single-line setext heading after a two-line definition")
    func singleLineHeadingAfterMultiLineDefinition() {
        let source = "> [a]:\n> /u\n> foo\n> ===\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                heading 1
                  text "foo"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:6
              block_quote @1:1-4:6
                heading 1 @3:3-4:6
                  text "foo" @3:3-3:6

            """)
    }

    @Test("CRLF line endings")
    func crlfTableAfterContinuedParagraph() {
        let source = "[a]:\r\n/u\r\n===\r\nx\r\na|b\r\n-|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "==="
                softbreak
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:4
              paragraph @3:1-4:2
                text "===" @3:1-3:4
                softbreak @-
                text "x" @4:1-4:2
              table @5:1-6:4
                table_header @5:1-5:4
                  table_cell align=none colspan=1 rowspan=1 @5:1-5:2
                    text "a" @5:1-5:2
                  table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                    text "b" @5:3-5:4

            """)
    }

    @Test("list item")
    func listItemTableAfterContinuedParagraph() {
        let source = "- [a]:\n  /u\n  ===\n  x\n  a|b\n  -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "==="
                    softbreak
                    text "x"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:6
              list bullet '-' tight @1:1-6:6
                item @1:1-6:6
                  paragraph @3:3-4:4
                    text "===" @3:3-3:6
                    softbreak @-
                    text "x" @4:3-4:4
                  table @5:3-6:6
                    table_header @5:3-5:6
                      table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                        text "a" @5:3-5:4
                      table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                        text "b" @5:5-5:6

            """)
    }

    @Test("lazy continuation lines never open a table")
    func lazyLinesStayParagraph() {
        let source = "> [a]:\n> /u\n> ===\nx\na|b\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x"
                  softbreak
                  text "a|b"
                  softbreak
                  text "-|-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:4
              block_quote @1:1-6:4
                paragraph @3:3-6:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x" @4:1-4:2
                  softbreak @-
                  text "a|b" @5:1-5:4
                  softbreak @-
                  text "-|-" @6:1-6:4

            """)
    }

    @Test("header and delimiter cell counts differ")
    func headerCellCountMismatch() {
        let source = "> [a]:\n> /u\n> ===\n> a|b|c\n> -|-\n> x\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "a|b|c"
                  softbreak
                  text "-|-"
                  softbreak
                  text "x"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:4
              block_quote @1:1-6:4
                paragraph @3:3-6:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "a|b|c" @4:3-4:8
                  softbreak @-
                  text "-|-" @5:3-5:6
                  softbreak @-
                  text "x" @6:3-6:4

            """)
    }

    @Test("a lone hyphen cannot interrupt the paragraph")
    func loneHyphenContinuesDefinitionParagraph() {
        let source = "> [a]:\n> /u\n> -\n> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "-"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:6
              block_quote @1:1-5:6
                paragraph @3:3-3:4
                  text "-" @3:3-3:4
                table @4:3-5:6
                  table_header @4:3-4:6
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "a" @4:3-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                      text "b" @4:5-4:6

            """)
    }

    @Test("tabs inside the continued lines")
    func contentTabsStayLiteral() {
        let source = "> [a]:\n> /u\n> ===\n> x\ty\n>\tz\n> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x\\ty"
                  softbreak
                  text "z"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-7:6
              block_quote @1:1-7:6
                paragraph @3:3-5:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x\\ty" @4:3-4:6
                  softbreak @-
                  text "z" @5:3-5:4
                table @6:3-7:6
                  table_header @6:3-6:6
                    table_cell align=none colspan=1 rowspan=1 @6:3-6:4
                      text "a" @6:3-6:4
                    table_cell align=none colspan=1 rowspan=1 @6:5-6:6
                      text "b" @6:5-6:6

            """)
    }

    @Test("list item in block quote")
    func tableInListInQuote() {
        let source = "> - [a]:\n>   /u\n>   ===\n>   a|b\n>   -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                list bullet '-' tight
                  item
                    paragraph
                      text "==="
                    table
                      table_header
                        table_cell align=none colspan=1 rowspan=1
                          text "a"
                        table_cell align=none colspan=1 rowspan=1
                          text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:8
              block_quote @1:1-5:8
                list bullet '-' tight @1:3-5:8
                  item @1:3-5:8
                    paragraph @3:5-3:8
                      text "===" @3:5-3:8
                    table @4:5-5:8
                      table_header @4:5-4:8
                        table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                          text "a" @4:5-4:6
                        table_cell align=none colspan=1 rowspan=1 @4:7-4:8
                          text "b" @4:7-4:8

            """)
    }

    @Test("NUL in the preceding line")
    func nulBeforeHeader() {
        let source = "> [a]:\n> /u\n> ===\n> x\u{0}\n> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x\u{FFFD}"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:6
              block_quote @1:1-6:6
                paragraph @3:3-4:5
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x\u{FFFD}" @4:3-4:5
                table @5:3-6:6
                  table_header @5:3-5:6
                    table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                      text "a" @5:3-5:4
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                      text "b" @5:5-5:6

            """)
    }

    @Test("NUL in the header row")
    func nulInHeader() {
        let source = "> [a]:\n> /u\n> ===\n> x\n> a|b\u{0}\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b\u{FFFD}"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:6
              block_quote @1:1-6:6
                paragraph @3:3-4:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x" @4:3-4:4
                table @5:3-6:6
                  table_header @5:3-5:7
                    table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                      text "a" @5:3-5:4
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:7
                      text "b\u{FFFD}" @5:5-5:7

            """)
    }

    @Test("tab-expanded setext heading")
    func tabExpandedSetextHeading() {
        let source = ">\t[a]: /u\n>\tfoo\n>\tbar\n>\t===\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                heading 1
                  text "foo"
                  softbreak
                  text "bar"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:6
              block_quote @1:1-4:6
                heading 1 @2:3-4:6
                  text "foo" @2:3-2:6
                  softbreak @-
                  text "bar" @3:3-3:6

            """)
    }

    @Test("list item setext heading")
    func listItemSetextHeading() {
        let source = "- [a]:\n  /u\n  foo\n  bar\n  ---\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  heading 2
                    text "foo"
                    softbreak
                    text "bar"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:6
              list bullet '-' tight @1:1-5:6
                item @1:1-5:6
                  heading 2 @3:3-5:6
                    text "foo" @3:3-3:6
                    softbreak @-
                    text "bar" @4:3-4:6

            """)
    }

    @Test("CRLF setext heading")
    func crlfSetextHeading() {
        let source = "[a]:\r\n/u\r\nfoo\r\n===\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              heading 1
                text "foo"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:4
              heading 1 @3:1-4:4
                text "foo" @3:1-3:4

            """)
    }

    @Test("delimiter row of a single hyphen")
    func loneHyphenDelimiterRow() {
        let source = "> [a]:\n> /u\n> ===\n> x\n> |-\n> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "x"
                  table_row
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                  table_row
                    table_cell align=none colspan=1 rowspan=1
                      text "-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-7:6
              block_quote @1:1-7:6
                paragraph @3:3-3:6
                  text "===" @3:3-3:6
                table @4:3-7:6
                  table_header @4:3-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "x" @4:3-4:4
                  table_row @6:3-6:6
                    table_cell align=none colspan=1 rowspan=1 @6:3-6:4
                      text "a" @6:3-6:4
                  table_row @7:3-7:6
                    table_cell align=none colspan=1 rowspan=1 @7:3-7:4
                      text "-" @7:3-7:4

            """)
    }

    @Test("tab-expanded table lines")
    func tabExpandedTable() {
        let source = "> [a]:\n> /u\n> ===\n>\tx\n>\ta|b\n>\t-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:6
              block_quote @1:1-6:6
                paragraph @3:3-4:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x" @4:3-4:4
                table @5:3-6:6
                  table_header @5:3-5:6
                    table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                      text "a" @5:3-5:4
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                      text "b" @5:5-5:6

            """)
    }

    @Test("two continued lines precede the header")
    func twoLinesBeforeHeader() {
        let source = "> [a]:\n> /u\n> ===\n> x\n> y\n> a|b\n> -|-\n> c|d\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "x"
                  softbreak
                  text "y"
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

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-8:6
              block_quote @1:1-8:6
                paragraph @3:3-5:4
                  text "===" @3:3-3:6
                  softbreak @-
                  text "x" @4:3-4:4
                  softbreak @-
                  text "y" @5:3-5:4
                table @6:3-8:6
                  table_header @6:3-6:6
                    table_cell align=none colspan=1 rowspan=1 @6:3-6:4
                      text "a" @6:3-6:4
                    table_cell align=none colspan=1 rowspan=1 @6:5-6:6
                      text "b" @6:5-6:6
                  table_row @8:3-8:6
                    table_cell align=none colspan=1 rowspan=1 @8:3-8:4
                      text "c" @8:3-8:4
                    table_cell align=none colspan=1 rowspan=1 @8:5-8:6
                      text "d" @8:5-8:6

            """)
    }

    @Test("a title on the line after the destination stays in the definition")
    func titleLineBelongsToDefinition() {
        let source = "> [a]: /u\n> 'T'\n> ===\n> [a]\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  link "/u" "T"
                    text "a"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:6
              block_quote @1:1-4:6
                paragraph @3:3-4:6
                  text "===" @3:3-3:6
                  softbreak @-
                  link "/u" "T" @4:3-4:6
                    text "a" @4:4-4:5

            """)
    }
}
