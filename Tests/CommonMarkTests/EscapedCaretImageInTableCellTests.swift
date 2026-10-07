/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An escaped-caret image `![\^…]` inside a GFM table cell.
@Suite("Escaped-caret image in a table cell")
struct EscapedCaretImageInTableCellTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink, .footnotes]

    private static func singleColumn(_ cellText: String) -> String {
        """
        document
          table
            table_header
              table_cell align=none colspan=1 rowspan=1
                text "o"
            table_row
              table_cell align=none colspan=1 rowspan=1
                text "\(cellText)"

        """
    }

    private static let paragraphBeforeTable = """
        document
          paragraph
            text "x ![^a]"
          table
            table_header
              table_cell align=none colspan=1 rowspan=1
                text "o"

        """

    /// Flag-off, a backslash-escaped caret makes `![\^…]` plain text, so the brackets stay literal with the image
    /// `!` kept and nothing read past the `]`.
    @Test func testEscapedCaretStaysLiteralWithoutBugCompatibility() {
        let cases: [(markdown: String, expected: String)] = [
            ("o\n|-\n![\\^\u{14}]", Self.singleColumn("![^\\u{14}]")),
            ("o\n|-\n![\\^a]", Self.singleColumn("![^a]")),
            ("o\n|-\n|![\\^a]|", Self.singleColumn("![^a]")),
            ("o\n|-\nx ![\\^ab]", Self.singleColumn("x ![^ab]")),
            ("o|p\n-|-\n![\\^a]|b", """
                document
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "o"
                      table_cell align=none colspan=1 rowspan=1
                        text "p"
                    table_row
                      table_cell align=none colspan=1 rowspan=1
                        text "![^a]"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

                """),
            ("o\n|-\n![\\^\u{14}]\nq", """
                document
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "o"
                    table_row
                      table_cell align=none colspan=1 rowspan=1
                        text "![^\\u{14}]"
                    table_row
                      table_cell align=none colspan=1 rowspan=1
                        text "q"

                """),
            ("o\n|-\n[\\^a]", Self.singleColumn("[^a]")),
            ("![\\^a]\n|-", """
                document
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "![^a]"

                """),
            ("![\\^a]|p\n-|-", """
                document
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "![^a]"
                      table_cell align=none colspan=1 rowspan=1
                        text "p"

                """),
            ("o|p\n-|-\nb|![\\^a]", """
                document
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "o"
                      table_cell align=none colspan=1 rowspan=1
                        text "p"
                    table_row
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                      table_cell align=none colspan=1 rowspan=1
                        text "![^a]"

                """),
            ("o\n|-\n![\\^\u{0}]", Self.singleColumn("![^\u{FFFD}]")),
            ("o\n|-\n![\\^a\\|]", Self.singleColumn("![^a|]")),
            ("x ![\\^a]\no\n|-", Self.paragraphBeforeTable),
            ("![\\^a]\n===", """
                document
                  heading 1
                    text "![^a]"

                """),
            ("> x ![\\^a]\n> o\n> |-", """
                document
                  block_quote
                    paragraph
                      text "x ![^a]"
                    table
                      table_header
                        table_cell align=none colspan=1 rowspan=1
                          text "o"

                """),
            ("x ![\\^a]\r\no\r\n|-", Self.paragraphBeforeTable),
            ("x ![\\^a]\t\no\n|-", Self.paragraphBeforeTable),
        ]
        for (markdown, expected) in cases {
            #expect(CmarkTreeDump.dump(markdown, options: Self.options) == expected, "\(markdown.debugDescription)")
        }
    }
}
