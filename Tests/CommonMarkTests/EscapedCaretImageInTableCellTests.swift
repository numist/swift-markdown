/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An escaped-caret image `![\^…]` in or next to a table (Tables (extension)).
@Suite("Escaped-caret image in or next to a table")
struct EscapedCaretImageInTableCellTests {
    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink, .footnotes,
    ]

    /// With no matching link reference definition, `[\^…]` and `![\^…]` are literal text, an image's `!` included, and
    /// the cell ends at its own `|` or line ending.
    @Test("an escaped-caret bracket or image without a matching definition is literal text", arguments: [
        ("o\n|-\n![\\^\u{14}]", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "![^\\u{14}]"

            """),
        ("o\n|-\n![\\^a]", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "![^a]"

            """),
        ("o\n|-\n|![\\^a]|", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "![^a]"

            """),
        ("o\n|-\nx ![\\^ab]", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x ![^ab]"

            """),
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
        ("o\n|-\n[\\^a]", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "[^a]"

            """),
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
        ("o\n|-\n![\\^\u{0}]", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "![^\u{FFFD}]"

            """),
        ("o\n|-\n![\\^a\\|]", """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "![^a|]"

            """),
        ("x ![\\^a]\no\n|-", """
            document
              paragraph
                text "x ![^a]"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"

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
        ("x ![\\^a]\r\no\r\n|-", """
            document
              paragraph
                text "x ![^a]"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"

            """),
        ("x ![\\^a]\t\no\n|-", """
            document
              paragraph
                text "x ![^a]"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"

            """),
    ])
    func escapedCaretStaysLiteral(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: Self.options) == tree)
    }
}
