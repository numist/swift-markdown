/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// When a table interrupts a paragraph, the lines before the header row form an ordinary paragraph (Paragraphs).
/// Only a cell's content unescapes `\|` (Tables (extension)), so a code span in those lines keeps its backslash
/// escapes literal (Code spans).
@Suite("Escaped pipe in a code span of a table's preceding paragraph")
struct TableCodeSpanPipeUnescapeTests {

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

    @Test("code span in a tab-continuation table's preceding paragraph keeps its escaped pipe")
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

    @Test("plain code span with an unescaped pipe is unaffected")
    func plainCodeSpanWithPipeUnaffected() {
        #expect(TreeDump.dump("`x|y`", options: [.tables]) == """
            document
              paragraph
                code "x|y"

            """)
    }
}
