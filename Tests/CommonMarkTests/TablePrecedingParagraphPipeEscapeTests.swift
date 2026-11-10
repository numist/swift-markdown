/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// When a table interrupts a paragraph, the lines before the header row form an ordinary paragraph (Paragraphs).
/// Only a cell's content unescapes `\|` (Tables (extension)), so in those lines a `\|` is a backslash escape (Backslash
/// escapes) and a code span keeps its backslash escapes literal (Code spans).
@Suite("Escaped pipe in the paragraph before a table")
struct TablePrecedingParagraphPipeEscapeTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options, sourceRanges: true)
    }

    @Test func backslashBeforePipeInCodeSpanIsLiteral() {
        #expect(tree("`a\\|b`\n| a |\n|-|") == """
            document @1:1-3:4
              paragraph @1:1-1:7
                code "a\\\\|b" @1:1-1:7
              table @2:1-3:4
                table_header @2:1-2:6
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "a" @2:3-2:4

            """)
    }

    @Test func escapedBackslashBeforePipeIsBackslash() {
        #expect(tree("x\\\\|y\n| a |\n|-|") == """
            document @1:1-3:4
              paragraph @1:1-1:6
                text "x\\\\|y" @1:1-1:6
              table @2:1-3:4
                table_header @2:1-2:6
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "a" @2:3-2:4

            """)
    }

    @Test func escapedPipeInBlockQuoteKeepsColumns() {
        #expect(tree("> a\\|b\n> c\n> | x |\n> |-|") == """
            document @1:1-4:6
              block_quote @1:1-4:6
                paragraph @1:3-2:4
                  text "a|b" @1:3-1:7
                  softbreak @-
                  text "c" @2:3-2:4
                table @3:3-4:6
                  table_header @3:3-3:8
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "x" @3:5-3:6

            """)
    }

    @Test func escapedPipeIsPipe() {
        #expect(tree("x\\|y\n| a |\n|-|") == """
            document @1:1-3:4
              paragraph @1:1-1:5
                text "x|y" @1:1-1:5
              table @2:1-3:4
                table_header @2:1-2:6
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "a" @2:3-2:4

            """)
    }

    @Test("code span in a table's preceding paragraph keeps its escaped pipe (backtick header)")
    func precedingParagraphCodeSpanKeepsEscapedPipe() {
        #expect(TreeDump.dump("`\\|`\n`\n|-", options: [.tables]) == """
            document
              paragraph
                code "\\\\|"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "`"

            """)
    }

    @Test("code span in a table's preceding paragraph keeps its escaped pipe (backslash header)")
    func precedingParagraphCodeSpanKeepsEscapedPipeBackslashHeader() {
        #expect(TreeDump.dump("`\\|`\n\\\n-|", options: [.tables]) == """
            document
              paragraph
                code "\\\\|"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "\\\\"

            """)
    }

    @Test("code span in a block-quote table's preceding paragraph keeps its escaped pipe")
    func precedingParagraphCodeSpanKeepsEscapedPipeInBlockQuote() {
        #expect(TreeDump.dump("> `\\|`\n> `\n> |-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  code "\\\\|"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "`"

            """)
    }

    @Test("code span before a tab-indented header row keeps its escaped pipe")
    func precedingParagraphCodeSpanKeepsEscapedPipeWithTabContinuation() {
        #expect(TreeDump.dump("`\\|`\n\tx\n|-", options: [.tables]) == """
            document
              paragraph
                code "\\\\|"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "x"

            """)
    }

    @Test("code span with no table keeps its escaped pipe")
    func standaloneCodeSpanKeepsEscapedPipe() {
        #expect(TreeDump.dump("`\\|`", options: [.tables]) == """
            document
              paragraph
                code "\\\\|"

            """)
    }

    @Test("preceding-paragraph code span keeps a non-pipe backslash escape")
    func precedingParagraphCodeSpanKeepsNonPipeEscape() {
        #expect(TreeDump.dump("`\\!`\n`\n|-", options: [.tables]) == """
            document
              paragraph
                code "\\\\!"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "`"

            """)
    }

    @Test("a code span with an unescaped pipe keeps the pipe")
    func plainCodeSpanWithPipeUnaffected() {
        #expect(TreeDump.dump("`x|y`", options: [.tables]) == """
            document
              paragraph
                code "x|y"

            """)
    }
}
