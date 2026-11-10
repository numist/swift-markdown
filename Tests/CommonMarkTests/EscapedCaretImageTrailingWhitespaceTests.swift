/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// `![\^…]` followed by spaces or tabs at the end of a line of a paragraph or heading.
@Suite("`![\\^…]` before trailing whitespace")
struct EscapedCaretImageTrailingWhitespaceTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink, .footnotes]

    /// With no matching link reference definition, `![\^…]` is literal text, and the spaces or tabs after it are not
    /// part of that text.
    @Test(arguments: [
        ("![\\^a] ", """
            document
              paragraph
                text "![^a]"

            """),
        ("![\\^a]\t", """
            document
              paragraph
                text "![^a]"

            """),
        ("![\\^a]  ", """
            document
              paragraph
                text "![^a]"

            """),
        ("![\\^ab] ", """
            document
              paragraph
                text "![^ab]"

            """),
        ("![\\^a] \n", """
            document
              paragraph
                text "![^a]"

            """),
        ("![\\^a] \r\n", """
            document
              paragraph
                text "![^a]"

            """),
        ("![\\^a] \n\nb", """
            document
              paragraph
                text "![^a]"
              paragraph
                text "b"

            """),
        ("x\n![\\^a] ", """
            document
              paragraph
                text "x"
                softbreak
                text "![^a]"

            """),
        ("> ![\\^a] ", """
            document
              block_quote
                paragraph
                  text "![^a]"

            """),
        ("> x\n> ![\\^a] ", """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "![^a]"

            """),
        ("> x\n![\\^a] ", """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "![^a]"

            """),
        ("- ![\\^a] ", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "![^a]"

            """),
        ("![\\^a] \n===", """
            document
              heading 1
                text "![^a]"

            """),
        ("![\\^a]\t\n===", """
            document
              heading 1
                text "![^a]"

            """),
        ("x\n![\\^a] \n===", """
            document
              heading 1
                text "x"
                softbreak
                text "![^a]"

            """),
        ("![\\^a]\t ", """
            document
              paragraph
                text "![^a]"

            """),
        ("[x]: /u\n![\\^a] ", """
            document
              paragraph
                text "![^a]"

            """),
        ("- [ ] ![\\^a] ", """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "![^a]"

            """),
        ("> \u{0}\n> ![\\^a] ", """
            document
              block_quote
                paragraph
                  text "\u{FFFD}"
                  softbreak
                  text "![^a]"

            """),
        ("- x\n![\\^a] ", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                    softbreak
                    text "![^a]"

            """),
        ("> ![\\^a] \n> ===", """
            document
              block_quote
                heading 1
                  text "![^a]"

            """),
        ("- ![\\^a] \n  ===", """
            document
              list bullet '-' tight
                item
                  heading 1
                    text "![^a]"

            """),
        ("![\\^a]\r\n", """
            document
              paragraph
                text "![^a]"

            """),
        ("![\\^a]  \nb", """
            document
              paragraph
                text "![^a]"
                linebreak
                text "b"

            """),
        ("x ![\\^a] \ny", """
            document
              paragraph
                text "x ![^a]"
                softbreak
                text "y"

            """),
        ("[\\^a] ", """
            document
              paragraph
                text "[^a]"

            """),
        ("# ![\\^a] ", """
            document
              heading 1
                text "![^a]"

            """),
    ])
    func escapedCaretStaysLiteral(markdown: String, expected: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == expected)
    }
}
